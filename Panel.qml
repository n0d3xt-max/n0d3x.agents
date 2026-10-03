import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // ---------- Sessions (Manage view) ----------
  // Dashboard <-> session list toggle. The list is scoped to the open tab and
  // covers this machine only; synced peers never contribute session detail.
  property bool showingSessions: false
  property string confirmDeleteId: ""
  property bool sessionBusy: false
  // Sessions filter (fuzzy title match) and grouping mode. Both reset with
  // the view itself in closeSessions() so a reopen never inherits stale UI.
  property string sessionQuery: ""
  property string sessionGroupBy: "date"

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var models: modelRows(provider)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || ""),
      // The raw label knows the window length ("5h", "7-day"); the title may
      // not (model-scoped limits are titled after their model). Pace math
      // needs the span, so it travels with the record.
      spanMs: windowSpanMs(label)
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  // Pace projection: linear burn from window start to now, extended to
  // reset. A fresh window has no pace yet and stays silent; sub-0.1%/h rates
  // skip the hourly prefix rather than printing a meaningless "0%/h".
  function paceTextFor(w) {
    if (!w || !(w.percent > 0)) return ""
    var remaining = root.resetMsFor(w)
    var span = Number(w.spanMs || 0)
    if (!(span > 0) || !(remaining > 0)) return ""
    var elapsed = span - remaining
    if (!(elapsed > 0)) return ""
    var projected = w.percent + (w.percent / elapsed) * remaining
    var text = ""
    if (span >= 3600000) {
      var perHour = Math.round((w.percent / elapsed) * 3600000 * 1000) / 10
      if (perHour > 0) text += perHour + "%/h · "
    }
    text += projected >= 1 ? "≈ full by reset" : "≈ " + Math.round(projected * 100) + "% by reset"
    return text
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · "
        + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    return rows.slice(0, 4)
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Only tabs with a wired sessions source get the Manage view. Others keep
  // the dashboard alone rather than an empty promise of a list.
  function sessionsManaged(p) {
    if (!p) return false
    var id = p.providerId
    return id === "opencode" || id === "codex"
      || id === "pi" || id === "gemini" || id === "crush"
      || id === "copilot" || id === "grok" || id === "hermes" || id === "cursor"
  }

  function sessionList(p) {
    if (!p || !p.recentSessions) return []
    return p.recentSessions
  }

  // Newest day first, sessions keep collector order (newest first) inside.
  // A non-empty query flattens everything into one "N of M" group, whatever
  // the grouping toggle says — mixed-date results under date headers confuse.
  function sessionGroups() {
    var list = root.sessionList(root.provider)
    var query = root.sessionQuery.trim().toLowerCase()
    var filtered = []
    for (var i = 0; i < list.length; i++) {
      var s = list[i] || {}
      if (query === "" || String(s.title || "").toLowerCase().indexOf(query) >= 0)
        filtered.push(s)
    }
    if (query !== "")
      return [{ date: "", items: filtered, total: list.length }]
    if (root.sessionGroupBy === "project")
      return root.projectGroups(filtered)
    var groups = []
    var byDate = {}
    for (var j = 0; j < filtered.length; j++) {
      var d = filtered[j] || {}
      var date = String(d.date || "")
      if (date === "") date = "Undated"
      if (!byDate[date]) {
        byDate[date] = []
        groups.push({ date: date, items: byDate[date], total: list.length })
      }
      byDate[date].push(d)
    }
    groups.sort(function(a, b) { return a.date < b.date ? 1 : (a.date > b.date ? -1 : 0) })
    return groups
  }

  // Project groups sort by most recent activity, not name — recency is what
  // the view is for. Sessions without a directory gather in Elsewhere, last.
  function projectGroups(list) {
    var groups = []
    var byDir = {}
    for (var i = 0; i < list.length; i++) {
      var s = list[i] || {}
      var dir = String(s.directory || "")
      var key = dir === "" ? "" : dir
      if (!byDir[key]) {
        byDir[key] = { date: key, items: [], total: list.length, latest: 0 }
        groups.push(byDir[key])
      }
      byDir[key].items.push(s)
      byDir[key].latest = Math.max(byDir[key].latest, Number(s.timestamp || 0))
    }
    groups.sort(function(a, b) {
      if (a.date === "" && b.date !== "") return 1
      if (b.date === "" && a.date !== "") return -1
      return b.latest - a.latest
    })
    return groups
  }

  function projectLabel(dir) {
    if (dir === "") return "Elsewhere"
    var clean = String(dir).replace(/\/+$/, "")
    var parts = clean.split("/")
    return parts.length > 0 ? parts[parts.length - 1] : clean
  }

  function groupLabel(date, count, total) {
    if (date === "") {
      var word = count === 1 ? "result" : "results"
      return count + " of " + total + " " + word
    }
    if (root.sessionGroupBy === "project") return root.projectLabel(date)
    if (date === root.todayDate()) return "Today"
    var y = new Date(root.nowMs)
    y.setDate(y.getDate() - 1)
    var yd = y.getFullYear()
      + "-" + String(y.getMonth() + 1).padStart(2, "0")
      + "-" + String(y.getDate()).padStart(2, "0")
    if (date === yd) return "Yesterday"
    return root.dayName(date) + " " + String(date).slice(5).replace("-", "/")
  }

  function sessionTime(ts) {
    var d = new Date(Number(ts) || 0)
    if (isNaN(d.getTime())) return ""
    return String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0")
  }

  function sessionMeta(s) {
    if (!s) return ""
    var parts = []
    var t = root.sessionTime(s.timestamp)
    if (t !== "") parts.push(t)
    parts.push(usage.formatTokenCount(Number(s.tokens || 0)) + " tokens")
    if (String(s.model || "") !== "") parts.push(String(s.model))
    // Cost appears only where metering exists (paid usage). Free-tier zeros
    // stay hidden rather than parading "$0.00" on every row.
    if (Number(s.costUsd || 0) >= 0.005) parts.push(root.formatMoney(Number(s.costUsd), "USD"))
    return parts.join(" · ")
  }

  // Period total over exactly what the view lists (filter-aware): the number
  // next to the caption answers "what did all of THIS cost".
  function sessionsCostTotal() {
    var groups = root.sessionGroups()
    var total = 0
    for (var g = 0; g < groups.length; g++) {
      var items = groups[g].items || []
      for (var i = 0; i < items.length; i++) total += Number((items[i] || {}).costUsd || 0)
    }
    return total
  }

  function openSessions() {
    if (!root.provider) return
    root.confirmDeleteId = ""
    root.showingSessions = true
    if (panelFlick) panelFlick.contentY = 0
  }

  function closeSessions() {
    root.confirmDeleteId = ""
    root.showingSessions = false
    root.sessionQuery = ""
    root.sessionGroupBy = "date"
    if (searchField) searchField.text = ""
    if (panelFlick) panelFlick.contentY = 0
    if (keyCatcher) keyCatcher.forceActiveFocus()
  }

  function resumeSession(s) {
    if (!s || root.sessionBusy || !root.provider) return
    root.sessionBusy = true
    sessionProcess.isDelete = false
    sessionProcess.command = ["n0d3x-agents-session", "resume",
      root.provider.providerId, String(s.id || ""), String(s.directory || "")]
    sessionProcess.running = true
  }

  function askDeleteSession(s) {
    if (s && !root.sessionBusy) root.confirmDeleteId = String(s.id || "")
  }

  function deleteSession(s) {
    if (!s || root.sessionBusy || !root.provider) return
    root.sessionBusy = true
    sessionProcess.isDelete = true
    sessionProcess.command = ["n0d3x-agents-session", "delete",
      root.provider.providerId, String(s.id || "")]
    sessionProcess.running = true
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: {
    root.closeSessions()
    if (panelFlick) panelFlick.contentY = 0
  }
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  } else {
    root.closeSessions()
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Resume/delete run through one helper so the panel stays provider-generic:
  // per-tool flags and destructive guards live in n0d3x-agents-session.
  Process {
    id: sessionProcess
    property bool isDelete: false
    running: false
    onExited: {
      if (sessionProcess.isDelete) {
        sessionProcess.isDelete = false
        root.confirmDeleteId = ""
        usage.refreshAll(true)
      }
      root.sessionBusy = false
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("agents/sessions", text.trim())
    }
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, sessionsColumn.implicitHeight), Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Sanctioned inline-editor pattern: while the search field holds focus
      // the catcher forwards everything, so typing s/r/j freely filters.
      blocked: searchField.activeFocus

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "s" || t === "S") root.openSessions()
        else if (t === "/" && root.showingSessions && !searchField.activeFocus) searchField.forceActiveFocus()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: root.showingSessions ? sessionsColumn.implicitHeight : column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          visible: !root.showingSessions
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: provider mark · name · plan ----------
          PanelHero {
            id: hero
            visible: !!root.provider
            width: parent.width
            title: root.provider ? root.provider.providerName : ""
            meta: root.heroMeta(root.provider)
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Item {
                id: heroMark
                property var candidates: root.iconCandidatesForProvider(root.provider, root.surface)
                // Provider objects are rebuilt on every refresh, which churns the
                // array's identity without changing its content. Restart the fallback
                // walk only when the URLs change: re-pointing source at a URL whose
                // load already failed emits no statusChanged, so an identity-only
                // reset would strand the walker on a missing -light twin.
                property string candidatesKey: candidates.join("\n")
                property int candidateIndex: 0
                onCandidatesKeyChanged: candidateIndex = 0

                width: Style.font.display
                height: Style.font.display

                Image {
                  id: heroMarkImage
                  anchors.fill: parent
                  source: heroMark.candidateIndex < heroMark.candidates.length ? heroMark.candidates[heroMark.candidateIndex] : ""
                  sourceSize.width: Style.font.display * 2
                  sourceSize.height: Style.font.display * 2
                  fillMode: Image.PreserveAspectFit
                  // Advancing source from inside its own status change trips the
                  // binding-loop detector; defer the step one tick.
                  onStatusChanged: if (status === Image.Error && heroMark.candidateIndex < heroMark.candidates.length)
                    Qt.callLater(function() { heroMark.candidateIndex++ })
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: heroMarkImage.status !== Image.Ready
                  text: button.text
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Balance / limits ----------
          PanelSeparator {
            visible: balanceSection.visible || limitsSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Column {
            id: limitsSection
            visible: root.limits.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LIMITS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.limits

              LimitRow {
                required property var modelData
                width: limitsSection.width
                window: modelData
              }
            }
          }

          // ---------- Usage ----------
          PanelSeparator {
            visible: usageSection.visible
            foreground: root.foreground
          }

          Column {
            id: usageSection
            visible: !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY DAY"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: usageSection.days

              DayRow {
                required property var modelData
                required property int index

                width: usageSection.width
                day: modelData
                ratio: Number(modelData.messageCount || 0) / usageSection.peak
                // By date, not by position: the Claude stats-cache fallback can
                // hand us a window that stops short of today.
                today: String(modelData.date || "") === root.todayDate()
              }
            }
          }

          // ---------- Models ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.models.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: "TOKENS BY MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.models

              ModelRow {
                required property var modelData
                width: modelSection.width
                row: modelData
                // Scaled to the heaviest model, so the top row is always full —
                // the same scale-to-peak the weekly chart uses for its busiest day.
                share: modelData.total / Math.max(1, root.models[0].total)
              }
            }
          }

          // ---------- Manage ----------
          // Footer action, the standard popover pattern: the whole dashboard
          // stays untouched, and one full-width button leads to the sub-view.
          Button {
            visible: !!root.provider && root.sessionsManaged(root.provider)
            width: parent.width
            text: "Manage sessions"
            selected: false
            hasCursor: false
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.openSessions()
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // ---------- Sessions view ----------
        // Same visual language as the dashboard: section headers, dim meta
        // text, bordered buttons. Back returns; Esc still closes the panel.
        Column {
          id: sessionsColumn
          visible: root.showingSessions
          width: panelFlick.width
          spacing: Style.space(12)

          Row {
            id: sessionsHeader
            width: parent.width
            spacing: Style.space(8)

            Button {
              id: sessionsBack
              anchors.verticalCenter: parent.verticalCenter
              text: "‹ Back"
              selected: false
              hasCursor: false
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.closeSessions()
            }

            Column {
              width: parent.width - sessionsBack.width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: "Sessions"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: {
                  var caption = (root.provider ? root.provider.providerName : "") + " · on this machine"
                  var total = root.sessionsCostTotal()
                  if (total >= 0.005) caption += " · " + root.formatMoney(total, "USD")
                  return caption
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }

          // ---------- Date / Project switch ----------
          // Same segmented pattern as the provider switch above: two equal
          // bordered buttons, selected state bound to the mode.
          Row {
            id: groupSwitch
            visible: root.sessionsManaged(root.provider) && root.sessionQuery.trim() === ""
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: (width - spacing) / 2
            readonly property var modes: [
              { key: "date", label: "Date" },
              { key: "project", label: "Project" }
            ]

            Repeater {
              model: groupSwitch.modes

              Button {
                required property var modelData

                width: groupSwitch.cellWidth
                text: modelData.label
                selected: root.sessionGroupBy === modelData.key
                hasCursor: false
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.sessionGroupBy = modelData.key
              }
            }
          }

          // ---------- Session search ----------
          // Filter lives with the list it filters. "/" focuses (vim-style);
          // Esc leaves via the catcher's close path, ✕ clears explicitly.
          Row {
            visible: root.sessionsManaged(root.provider)
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: searchGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            TextField {
              id: searchField
              width: parent.width - searchGlyph.width - clearSearch.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              placeholderText: "Filter sessions…  ( / )"
              foreground: root.foreground
              verticalPadding: Style.spacing.controlPaddingY
              onTextChanged: root.sessionQuery = searchField.text
              Keys.onEscapePressed: keyCatcher.forceActiveFocus()
            }

            Button {
              id: clearSearch
              anchors.verticalCenter: parent.verticalCenter
              visible: searchField.text !== ""
              text: "✕"
              selected: false
              hasCursor: false
              bordered: true
              foreground: root.dim
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: {
                searchField.text = ""
                keyCatcher.forceActiveFocus()
              }
            }
          }
          Text {
            visible: !!root.provider && !root.sessionsManaged(root.provider)
            width: parent.width
            text: "Session management isn't wired for this provider yet — its usage is counted, but there is no local session list to manage."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !!root.provider && root.sessionsManaged(root.provider) && root.sessionList(root.provider).length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No sessions recorded here yet."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.showingSessions ? root.sessionGroups() : []

            Column {
              required property var modelData
              width: sessionsColumn.width
              spacing: Style.spacing.md

              PanelSectionHeader {
                width: parent.width
                text: root.groupLabel(modelData.date, modelData.items.length, modelData.total || 0)
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: modelData.items

                SessionRow {
                  required property var modelData
                  width: sessionsColumn.width
                  session: modelData
                }
              }
            }
          }
        }
      }
    }
  }

  // A limit window: label and percentage, meter, and reset countdown.
  component LimitRow: Column {
    id: limitRow
    property var window: null

    readonly property bool alarming: window && window.percent >= 0.9

    spacing: Style.space(6)

    Item {
      width: parent.width
      implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

      Text {
        id: limitLabel
        textFormat: Text.PlainText
        // A model-scoped window is titled after its model, and those names run
        // long enough to reach the percentage, so the title gives way first.
        text: limitRow.window ? limitRow.window.title : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.right: limitValue.left
        anchors.rightMargin: Style.spacing.sm
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: limitValue
        textFormat: Text.PlainText
        text: limitRow.window && limitRow.window.percent >= 0
          ? Math.round(limitRow.window.percent * 100) + "%"
          : "—"
        color: limitRow.alarming ? root.urgent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    Meter {
      width: parent.width
      value: limitRow.window ? limitRow.window.percent : -1
      alarming: limitRow.alarming
    }

    Text {
      id: resetText
      textFormat: Text.PlainText
      width: parent.width
      text: {
        var remainingMs = root.resetMsFor(limitRow.window)
        return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : ""
      }
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    Text {
      textFormat: Text.PlainText
      visible: text !== ""
      width: parent.width
      text: root.paceTextFor(limitRow.window)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // One row per day: label, bar, tokens. Today is picked out in full
  // foreground so the week reads as a run-up to right now.
  component DayRow: Item {
    id: dayRow
    property var day: null
    property real ratio: 0
    property bool today: false

    implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Style.spacing.sm

    Text {
      id: dayLabel
      textFormat: Text.PlainText
      text: root.dayLabel(dayRow.day ? dayRow.day.date : "", dayRow.today)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: dayRow.today
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    Rectangle {
      id: dayTrack
      anchors.left: dayLabel.right
      anchors.right: dayValue.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))
      radius: height / 2
      color: root.track

      Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        radius: parent.radius
        width: parent.width * root.clamp(dayRow.ratio, 0, 1)
        color: dayRow.today ? root.foreground : root.alpha(root.foreground, 0.55)

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }
    }

    Text {
      id: dayValue
      textFormat: Text.PlainText
      text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
      color: dayRow.today ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      horizontalAlignment: Text.AlignRight
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(52)
    }

    MouseArea {
      id: dayHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: dayHover.containsMouse
      text: root.dayTooltip(dayRow.day, dayRow.today)
      fontFamily: root.fontFamily
    }
  }

  // Model rows read as a table: the share bar fills the row behind the label
  // instead of stacking under it, which keeps the whole dashboard on one screen.
  component ModelRow: Item {
    id: modelRow
    property var row: null
    property real share: 0

    implicitHeight: modelName.implicitHeight + Style.spacing.lg

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.05)
    }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: parent.width * root.clamp(modelRow.share, 0, 1)
      radius: Style.cornerRadius
      color: root.alpha(root.foreground, 0.14)

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

    Text {
      id: modelName
      textFormat: Text.PlainText
      text: modelRow.row ? modelRow.row.name : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.right: modelTokens.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: modelTokens
      textFormat: Text.PlainText
      text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
      id: modelHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
    }

    PanelToolTip {
      visible: modelHover.containsMouse
      text: root.modelTooltip(modelRow.row)
      fontFamily: root.fontFamily
    }
  }

  // One session: title, dim meta line, and Resume/Delete actions. Delete
  // arms an inline confirm instead of a dialog, the popover-friendly
  // pattern — nothing modal ever covers the list you are deciding from.
  component SessionRow: Column {
    id: sessionRow
    property var session: null
    readonly property bool confirming: !!sessionRow.session
      && root.confirmDeleteId === String(sessionRow.session.id || "")

    spacing: Style.space(6)

    Text {
      textFormat: Text.PlainText
      width: parent.width
      text: sessionRow.session ? String(sessionRow.session.title || "Untitled session") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Row {
      visible: !sessionRow.confirming
      width: parent.width
      spacing: Style.space(8)

      Text {
        id: sessionMeta
        textFormat: Text.PlainText
        width: parent.width - resumeButton.width - deleteButton.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        text: root.sessionMeta(sessionRow.session)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Button {
        id: resumeButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Resume"
        selected: false
        hasCursor: false
        bordered: true
        opacity: root.sessionBusy ? 0.5 : 1
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: {
          if (!root.sessionBusy) root.resumeSession(sessionRow.session)
        }
      }

      Button {
        id: deleteButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Delete"
        selected: false
        hasCursor: false
        bordered: true
        opacity: root.sessionBusy ? 0.5 : 1
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: root.askDeleteSession(sessionRow.session)
      }
    }

    Row {
      visible: sessionRow.confirming
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width - confirmButton.width - keepButton.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Delete this session?"
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      Button {
        id: confirmButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Delete"
        selected: false
        hasCursor: false
        bordered: true
        opacity: root.sessionBusy ? 0.5 : 1
        foreground: root.urgent
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: {
          if (!root.sessionBusy) root.deleteSession(sessionRow.session)
        }
      }

      Button {
        id: keepButton
        anchors.verticalCenter: parent.verticalCenter
        text: "Keep"
        selected: false
        hasCursor: false
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: root.confirmDeleteId = ""
      }
    }
  }
}
