# SayMark iOS App UI Redesign Prompt

You are a top-tier iOS UI designer. I need you to generate a complete set of high-fidelity iOS app design mockups for iPhone 15 Pro (393x852pt). Design reference style: Apple Notes + Things 3 + Notion + WeChat voice input. Clean, modern, warm, productivity-tool aesthetic.

---

## App Overview

**SayMark** — an AI-powered voice notebook. Users hold a mic button and speak; AI transcribes and generates structured markdown notes. Natural-language voice/text commands control files/folders (CRUD + move). Also functions as a calendar and reminder app.

**Navigation**: Bottom Tab Bar with 3 tabs: [Files] [Calendar] [Reminders]. Plus a full-screen Chat drawer accessible via floating button, sliding in from the right (not a tab).

**Color Palette:**
- Primary: iOS Blue (#007AFF)
- Accent/Warnings: Orange (#FF9500) — calendar dots, bell icons, reminder badges, AI thinking cards
- Danger: Red (#FF3B30) — delete buttons, cancel zone
- Success: Green (#34C759) — text-mode zone, confirm buttons
- Background: iOS grouped background (#F2F2F7)
- Card/Surface: White (#FFFFFF)
- Text Primary: #000000
- Text Secondary: #8E8E93

**Typography**: SF Pro Display (titles), SF Pro Text (body), PingFang SC (Chinese). Use system font scale.

**Icon Set**: SF Symbols. Key icons: folder.fill, doc.text, calendar.badge.clock, bell.fill, mic.fill, bubble.left.and.bubble.right.fill, pencil, trash, brain.head.profile, arrow.uturn.backward.

---

## Generate These Pages

### Page 1: File List (Home / Tab "Files")

Two variants: empty state + populated state with nested folders.

**Nav Bar**: Title "SayMark" left-aligned. Right side: "+" plus button + chat bubble icon (opens AI chat drawer).

**List** (insetGrouped style): Tree structure with DisclosureGroup expand/collapse.
- Folder row: folder.fill icon (tint blue) + name. Indented children when expanded.
- Note row: doc.text icon (gray) + name + updated time (caption, gray).
- Event row: calendar.badge.clock icon (orange) + name + updated time + orange "日程" capsule badge (white text, #FF9500 bg, 6px padding, capsule shape).

Swipe left reveals: red "Delete" trash button, blue "Rename" pencil button.
Long press shows context menu: Rename / Delete / "New Item" (folders only).

**Empty State**: Centered illustration (a stylized notebook with microphone) + "还没有笔记" heading + "按住话筒开始说话吧" subtext in gray.

**Floating Button**: Bottom-right corner, 56px circle, accentColor bg, mic.fill icon white, shadow. Floats above Tab Bar.

### Page 2: Calendar (Tab "Calendar")

**Month Header**: "< 2026年8月 >" with chevron buttons, centered.

**Weekday Header**: "一 二 三 四 五 六 日" row, gray caption, evenly spaced.

**Date Grid** (7 columns): 
- Each cell: day number (14pt), centered 28x28 circle.
- Today: bold blue number, no fill.
- Selected day: white number, blue circle fill.
- Other month: gray number.
- Orange dot (5px) below dates with events.

**Event List Below Divider**:
- Selected date label: "8月9日" subheadline.
- Event rows: title (body, medium weight) + content preview (caption, gray, 2-line max) + time (caption, blue, right-aligned).
- Empty: "当天无日程" centered gray text.

### Page 3: Reminders (Tab "Reminders")

Two variants: populated + empty.

**Nav Bar**: "提醒" title. Refresh button (top-right) when list is not empty.

**List** (insetGrouped):
- Each row: orange bell.fill icon left + event title (medium) + date/time row below (calendar icon + "2026-08-09 14:00" caption gray) + "提前30分钟" orange capsule badge + bell.slash cancel button (right).
- Swipe to cancel or tap bell.slash → confirmation dialog.

**Empty State**: Large bell.slash icon (gray) + "暂无提醒" heading + "还没有设置任何日程提醒" subtext.

### Page 4: AI Chat (Slide-in Drawer)

Full-screen, slides in from right. Two variants: empty + active conversation.

**Nav Bar**: Hamburger menu (left, opens history sidebar) + "新建" compose button (right, when conversation exists).

**Message List** (ScrollView):
- User bubble: right-aligned, blue (#007AFF) bg, white text, 16px corner radius.
- AI bubble: left-aligned, light gray (#E5E5EA) bg, black text, 16px corner radius.
- **Thinking Card** (shown before AI reply): collapsed card with 🧠 orange brain icon + "正在处理..." title + step count badge. Expanded: vertical list of thinking steps (caption, 0.8 opacity orange), live typewriter text animating. On complete: auto-collapses to "处理完成（3步）".
- Streaming indicator: 3 bouncing dots below AI bubble during streaming.

**Input Bar** (bottom, above safe area):
- mic.fill circle button (left, same press-to-record interaction as Page 1 floating button).
- Multi-line text field (center, 1-5 lines auto-grow, roundedBorder style).
- Arrow-up send button (right, accentColor, visible only when text non-empty).

**History Sidebar** (slides from left, 75% width):
- Semi-transparent black overlay behind.
- "历史会话" header + compose button.
- Conversation list: title + preview text per row. Tap to switch.

**Empty State**: Large chat bubble icon + "开始对话" heading + "你可以和我聊天，我会记住上下文。\n也可以问我关于笔记和日程的问题。" subtext.

### Page 5: Note Detail (Push from File List)

Two variants: view mode + edit mode.

**View Mode**:
- Nav title: note name (inline). Right: "Edit" pencil button.
- Markdown rendered content (full scroll):
  - # Heading: title2, bold
  - ## Sub: title3, bold
  - ### Sub-sub: headline
  - > Quote: italic gray + 3px left border (gray 0.3)
  - - Bullet: "•" prefixed
  - 1. Number: "1." prefixed, medium weight number
  - **Bold**: bold
  - *Italic*: italic
- **Bottom Toolbar** (gray grouped bg, 3 buttons evenly spaced):
  - Left: arrow.uturn.backward undo button (visible when undo available)
  - Center: mic.fill button (press to record voice edit command)
  - Right: pencil edit button
- Voice edit loading overlay: ProgressView + "正在调整笔记..." centered, semi-transparent white bg.

**Edit Mode**:
- RoundedBorder text field for name at top.
- TextEditor for content below (min 320pt height, gray border).
- Nav right "保存" save button.

### Page 6: Voice Input (Command Mode, presented as Sheet)

**Nav**: "语音输入" title, "关闭" dismiss button left.

**Body**:
- Multi-line text field (1-4 lines), placeholder: "说话或输入文字，例如：明天下午3点面试 / 定位到工作文件夹".
- mic.fill button beside text field (press-to-record).
- Full-width "发送" blue button (12px radius, send/loading states).
- **Result card** (after sending): green checkmark + "成功" header + message (success) OR red xmark + "失败" + error (failure). Gray bg, rounded 12px.

### Page 7: New Item Sheet

Sheet with Form: Picker (folder/file type selector, only "folder" at root level) + name text field. Nav: "取消" left, "创建" right (disabled when name empty).

### Page 8: Rename Sheet

Sheet with Form: name text field (pre-filled). Nav: "取消" left, "确定" right (disabled when empty).

### Page 9: Delete Confirmation Dialog

System alert style. Folder: "确定删除文件夹？" + "将删除「工作」及其内部 5 个文件。此操作不可撤销。" + red "删除" + "取消". File: same but "确定删除笔记？" + "将删除笔记「XXX」。此操作不可撤销。"

### Page 10: Recording Overlay (Press-and-Hold Mic)

Full-screen semi-transparent black overlay (0.4 opacity). Three visual zones based on drag position, triggered by holding the mic button for 0.15s then dragging:

**Zone 1 — Normal (default, no drag)**:
- Center-top: 6 vertical rounded bars (white, 3x20px each, heights randomly animating 10-30px) — audio waveform.
- "松开 发送" white bold headline.
- Live transcript text below (white 0.8, max 3 lines, centered).
- Bottom hints: "xmark 松开取消" (left) + "转文字 textformat" (right), white 0.6 caption.

**Zone 2 — Cancel (drag up >60px + left)**:
- Large xmark.circle.fill icon (48pt, red) centered.
- "松开 取消" red bold headline.
- Red 0.15 opacity rounded card background behind.

**Zone 3 — Text Mode (drag up >60px + right)**:
- Large textformat.alt icon (48pt, green) centered.
- "松开 转文字" green bold headline.
- Green 0.15 opacity rounded card background behind.

### Page 11: Text Edit Panel (Bottom Sheet after Recording)

Bottom sheet (white bg, rounded top 16px, shadow). Semi-transparent overlay behind.

- Top row: xmark close (gray circle) + "确认文字" title (bold) + green checkmark confirm (white on green circle).
- TextEditor in middle (min 100pt, gray 0.1 bg, rounded 8px, pre-filled with transcript).
- Padding 20px, bottom margin for safe area.

---

## Key Interactions to Visualize

1. **Hold-to-record**: Press mic → overlay appears → wave animation → drag up for cancel/text-mode zones.
2. **Swipe actions**: Red delete + blue rename revealed on horizontal swipe.
3. **Pull-to-refresh**: File list and reminders support pull-down refresh.
4. **Slide-in panels**: Chat drawer (full-screen right), history sidebar (75% left).
5. **Expand/collapse**: Folder rows expand inline showing children; thinking cards expand showing steps.

---

## Critical Design Improvements Needed (vs current app)

- Current app uses bare SwiftUI defaults — needs brand identity, custom styling
- Empty states need illustrations, not just text
- Recording overlay needs glassmorphism/refined blur effects
- Calendar needs better visual hierarchy between month grid and event list
- Markdown rendering needs proper typography hierarchy
- App needs a cohesive color system, not just system defaults
- Add subtle micro-interactions and transitions

---

## Output Requirements

Generate a complete UI kit with all 11 pages above, in iPhone 15 Pro dimensions. Include both light mode designs. Provide each page as a separate frame showing realistic content (Chinese text). Include any modal/overlay states as separate frames or layers. Use the specified color palette and icon set consistently across all screens.
