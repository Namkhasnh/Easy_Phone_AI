# EasyPhone AI — UI_SCREENS.md

> Audience: an AI coding agent (Claude Code) building the SwiftUI app in Xcode. Hierarchy (D-279): `DECISIONS.md` → `EasyPhone-AI-Spec.md` → `DATA_MODEL.md` → `API_CONTRACT.md` → `AI_PROMPTS.md` → `ARCHITECTURE.md` → **this file**. This file defines **screens, layouts, navigation, design tokens and every Vietnamese UI string**. It never changes a state, field id, endpoint, rule or quota. Conflict → the other doc wins; flag with `// TODO(decision):`. Choices made here (P-31 – P-40, §12) are approved as D-266 – D-275.
> **Do not invent UI.** A screen, element or string not listed here → simplest option + `// TODO(spec):`.
## 0. Rules
1. **Every visible string lives in `Localizable.xcstrings`** (D-003) under the key shown here (`vi` = source text, `en` = translate later). Views use `Text(LocalizedStringKey("…"))` or `UserMessage(key:args:)` (P-30). No literals.
2. `{x}` = a format argument. In xcstrings use `%@` / `%lld` in the same order. Never concatenate strings.
3. **Tone (P-34):** the app calls itself **"mình"**, the user **"bạn"**. Short sentences, no jargon (D-184), no "Submit/OK".
4. **Max 2 primary buttons per screen** (D-182); every button is full width, min height 56pt, text never truncated at AX5.
5. **State = icon + text, never color alone** (D-183). State labels/icons = `DATA_MODEL.md` §8 verbatim (`state.<raw>`).
6. Field labels come from `field.<kind>.<id>` (D-220, §10.2); the LLM never writes UI text.
7. Every screen has a `#Preview` with `AppEnvironment.mock(...)` (D-206); preview data shows the badge "Dữ liệu mẫu" (D-189).
8. iPhone only, portrait-first, safe-area aware (D-010). Landscape works but is not optimized.
## 1. Design tokens (`Core/UI/Tokens.swift`, P-32)
### 1.1 Colors (asset catalog, light / dark; all text pairs verified ≥ 4.5:1) — "Khoai" palette (D-291)
System blue fails 4.5:1 on white for normal text, so the app uses its own tokens. Name = asset name. Palette taken
from the app icon (D-291): cream / navy-night backgrounds, warm brown text, sweater-blue `primary`, honey-fur accent.

| Token | Light | Dark | Use | Contrast (measured, light / dark) |
|---|---|---|---|---|
| `bg` | `#FFFBF5` | `#0D1726` | screen background (warm cream / navy night) | — |
| `surface` | `#F6EEE4` | `#18263B` | cards, field rows, sheets | — |
| `textPrimary` | `#2B2118` | `#F7F1EA` | titles, values | 13.7 / 13.6 on `surface` |
| `textSecondary` | `#5A4A3A` | `#CDBFAF` | hints, subtitles | 7.4 / 8.5 on `surface` |
| `primary` | `#1F5FA8` | `#8CC2F2` | primary button fill, links, mic (Khoai's sweater) | 5.6 / 8.1 as text on `surface` |
| `onPrimary` | `#FFFFFF` | `#0D1726` | text/icon on `primary` | 6.4 / 9.5 |
| `secondaryFill` | `#E3EEFA` | `#1B3350` | secondary button fill (text = `primary`) | 5.5 / 6.8 |
| `honey` | `#F3CB8D` | `#E2B26E` | **fill only** (Khoai's fur): Home greeting card, mic listening ring, EmptyState circle; text on it = asset `onHoney` (= `textPrimary` light / `bg` dark); never a text color | 10.3 / 9.3 |
| `success` | `#1E7B34` | `#5BD07A` | `succeeded`, `userMarkedDone` icon+text | 4.6 / 7.8 on `surface` |
| `warning` | `#7A4F00` | `#FFC24D` | "Kiểm tra lại" text on `warningBg` | 6.4 / 8.5 |
| `warningBg` | `#FFF1D6` | `#3A2C00` | low-confidence / OCR / ambiguity row fill | — |
| `danger` | `#B42318` | `#FF7A6E` | delete, `failed`, errors (text on fill: `onPrimary`, 6.6 / 7.1) | 5.7 / 6.0 on `surface` |
| `border` | `#7A6A5A` | `#9A8B7B` | field outlines, dividers that carry meaning | 4.5 / 4.6 on `surface` |
| `focusRing` | `primary` | `primary` | 3pt outline on keyboard/VoiceOver focus | — |

Rules: no gradients or star decoration behind text. Support **Increase Contrast** (`colorSchemeContrast == .increased` → borders 2pt, `secondaryFill` → `surface` with `primary` 2pt border). Never put `textSecondary` on `warningBg`. No gradients, no opacity < 1 for text.
### 1.2 Typography (Dynamic Type only, P-33)
Only SwiftUI text styles; **no fixed point sizes**. `display`, `title`, `button` use the rounded design
(`.fontDesign(.rounded)`, SF Pro Rounded, D-291); the rest use the default design. Sizes below are the iOS defaults at "Large" for reference.

| Token | Text style | Default pt | Weight | Use |
|---|---|---|---|---|
| `display` | `.largeTitle` | 34 | bold | screen title (Home greeting, result title) |
| `title` | `.title2` | 22 | bold | section / sheet titles, Review step title |
| `fieldValue` | `.title3` | 20 | regular | field values, transcript, list row title |
| `button` | `.title3` | 20 | semibold | all button labels |
| `body` | `.body` | 17 | regular | messages, explanations |
| `label` | `.callout` | 16 | semibold | field labels, badges |
| `caption` | `.footnote` | 13 | regular | **only** legal text and version number |

Floor: no informational text smaller than `.callout`. Line limit = none (`.lineLimit(nil)`), `minimumScaleFactor` never below 1. At AX sizes (`dynamicTypeSize.isAccessibilitySize`) every `HStack` of label+value becomes a `VStack`.
### 1.3 Spacing, radius, sizes
| Token | Value | Token | Value |
|---|---|---|---|
| `space.xs` | 4 | `radius.button` | 14 |
| `space.s` | 8 | `radius.card` | 16 |
| `space.m` | 12 | `radius.sheet` | system |
| `space.l` | 16 | `screenPadding` (horizontal) | 20 |
| `space.xl` | 24 | `sectionGap` | 32 |
| `space.xxl` | 32 | `rowMinHeight` (list/field row) | 64 |
| `button.minHeight` | **56** (D-182) | `micButton` (Home) | **120** diameter (D-182) |
| `micButton.listening` | 140, pulsing ring | `icon.inline` / `icon.row` / `icon.hero` | 24 / 28 / 56 |
| `tapTarget.min` (any control) | 44 × 44 | `stepBadge` | 32 diameter |

Grid = 4pt. Buttons stack vertically at the bottom of the screen (primary first, then secondary), pinned above the safe area in a `safeAreaInset(edge: .bottom)` with `bg` fill. Motion: default SwiftUI; respect **Reduce Motion** (no pulse, cross-fade only). Haptics: `.success` on `succeeded`, `.warning` on `failed`, none elsewhere.
## 2. Shared components (`Core/UI/Components/`)
| Component | Spec |
|---|---|
| `PrimaryButton(titleKey, role)` | `primary` fill, `onPrimary` text, `button` font, full width, 56pt. `role: .destructive` → `danger` fill. Disabled = `surface` fill + `textSecondary` + reason text below (never hidden). |
| `SecondaryButton(titleKey)` | `secondaryFill` + `primary` text, same size. |
| `TextLinkButton` | `primary` text, `body` font, 44pt min height (legal links, "Xem tất cả"). |
| `FieldRow(field)` | `surface` card, label (`label`) above value (`fieldValue`), chevron, 64pt min. Empty value → "Chưa có" in `textSecondary`. `needsReview` → `warningBg` + icon `exclamationmark.triangle` + "Kiểm tra lại". OCR source → extra `TextLinkButton` "Xem ảnh gốc". Ambiguity → question text + "Chọn". Tap → `FieldEditorSheet`. |
| `StateBadge(state, args)` | SF Symbol + `state.<raw>` text, `label` font; color per §1.1 (`success`, `danger`, else `textSecondary`). |
| `Banner(UserMessage, action?)` | top of content, `surface` + 4pt left bar (`danger` / `warning`), icon + `body` + optional `SecondaryButton`. |
| `Toast(key, undo?)` | bottom, 4 s (8 s with VoiceOver on), announced via `AccessibilityNotification.Announcement`; optional "Hoàn tác". |
| `StepIndicator(current,total)` | "Bước {n}/{total}" + dots; dots decorative (`accessibilityHidden`). |
| `ListeningMic` | circle `primary`, `mic.fill` 56pt; listening → `stop.fill`, `honey` ring pulse (light: plus a 2pt `primary` outline, honey alone is 1.5:1 on `bg`, D-291), label changes. |
| `EmptyState(icon, titleKey, bodyKey)` | centered, `icon.hero` (default `pawprint.fill`, D-291) on an 88pt `honey` circle, `title` + `body`. |
| `ConfirmSheet` | `.presentationDetents([.medium, .large])`, title, body, primary + secondary. Used for every destructive confirm. |
| `MascotView(pose, size)` | Guide mascot **Khoai** (P-41, D-289). Owner-supplied art, asset `mascot.<pose>`: `greeting`, `listening`, `thinking`, `asking`, `happy`, `sorry`. Decorative (`accessibilityHidden`), not a button, no tap action, no text of its own. Idle breathe/bounce, tilt on `thinking`, small hop on `happy` (`PhaseAnimator`); Reduce Motion → static. Hidden everywhere when `settings.pet` is off. |
## 3. Screen inventory
| ID | Screen | Presentation | Route / trigger (ARCHITECTURE §2.2) | Phase |
|---|---|---|---|---|
| S01 | Sign-in | root (session `.signedOut`) | `AppState.session` | 0 |
| S02 | Home | root `NavigationStack` | default | 1B |
| S03 | Conversation (listen / type / follow-up / unsupported) | push | `.conversation(UUID?)` | 1B |
| S04 | Review (all kinds, linked steps, result) | push | `.review(UUID)` | 1A |
| S05 | Field editor | sheet over S04 | tap `FieldRow` / "Sửa" | 1A |
| S06 | Picker (contact / phone / date / place / event) | sheet over S04 | ambiguity "Chọn" | 1C |
| S07 | Copy guide (unverified channel) | push from S04 | after "Xác nhận" on `sms` with `channel ≠ sms` | 1C |
| S08 | Hand-off return prompt | sheet, any screen | `HandoffPromptCoordinator` | 1C |
| S09 | Photo capture + OCR progress + retake | push | `.ocr` | 1D |
| S10 | Source image | full-screen cover over S04 | "Xem ảnh gốc" | 1D |
| S11 | Calendar today | push | `.calendarToday` (P-31) | 1C |
| S12 | Reminders | push | `.reminders` (P-31) | 1C |
| S13 | Places (search, map preview, saved list) | push | `.places` | 1C |
| S14 | History | push | `.history` | 1A |
| S15 | Settings (+ Nicknames, Saved places, Permissions) | push | `.settings` | 1A/1G |
| S16 | Paywall | sheet | `.paywall`, 402 free | 1F |
| S17 | Quota reached (premium) | sheet | 402 premium (D-241) | 1F |
| S18 | Permission explainer / denied | sheet | first use before "Xác nhận" (D-185) / `permission.*.denied` | 1C |
| S19 | Update required | full-screen cover, blocking | `AppState.blockingScreen` (426) | 0 |
| S20 | Destructive confirms (delete account, clear data, sign out) | `ConfirmSheet` | Settings | 1G |

Widgets, Control and Siri are not screens: they only open S03 in listening mode (`easyphone://listen`, D-172).
## 4. Navigation flow
```
Launch ─▶ session? ──no──▶ S01 ──signed in──▶ S02
          │ yes                                 │
          ▼                                     ├─ mic / text "Gửi" ─▶ S03 ─parse ok─▶ S04 (draft)
         S02 ◀── easyphone://listen, Siri,      │                      ├─ followUp ─▶ S03 (question) ─▶ S04
              Action Button, Control, widget    │                      ├─ unsupported ─▶ S03 "Chưa hỗ trợ"
              (S03 opens in listening mode)     │                      └─ 402 ─▶ S16 (free) / S17 (premium)
                                                ├─ "Chụp ảnh giấy tờ" ─▶ S09 ─text─▶ S04 (ocr step) ─"Tiếp tục"─▶ S04 (next step)
                                                ├─ unfinished task row ─▶ S04 at draft.currentStep
                                                ├─ "Lịch hôm nay" ─▶ S11 ─event "Sửa"/"Xóa"─▶ S04 (update/delete)
                                                ├─ "Lời nhắc" ─▶ S12 ─"Sửa"/"Xóa"/"Nhắc lại sau"─▶ S04
                                                ├─ toolbar "Lịch sử" ─▶ S14 ─row─▶ S04
                                                └─ toolbar "Cài đặt" ─▶ S15 ─▶ S16 / S20 / S13
S04 "Xác nhận" ─▶ permission notDetermined? ─▶ S18 explainer ─▶ execute
   ├─ succeeded ─▶ S04 result card ─"Tiếp tục: …"─▶ next step | "Xong" ─▶ S02
   ├─ SMS composer (system) ─sent─▶ result │ cancelled ─▶ S04 awaitingApproval
   ├─ tel:// / Maps / copy ─▶ other app ─return─▶ S08 "Bạn đã … xong chưa?"
   ├─ unknown ─▶ S04 card "Tôi đã làm xong" / "Thử lại"
   └─ failed ─▶ S04 error card "Thử lại" / "Hủy"
Any API 426 ─▶ S19 (blocks everything). Any 401 after refresh ─▶ S01 (drafts kept).
```
Back button always returns without losing data (autosave, D-104). Swipe-to-dismiss on sheets = "Hủy" of that sheet.
## 5. Common strings (`common.*`)
| Key | vi | Key | vi |
|---|---|---|---|
| `common.confirm` | Xác nhận | `common.edit` | Sửa |
| `common.cancel` | Hủy | `common.save` | Lưu |
| `common.close` | Đóng | `common.done` | Xong |
| `common.retry` | Thử lại | `common.continue` | Tiếp tục |
| `common.later` | Để sau | `common.choose` | Chọn |
| `common.yesDone` | Đã xong | `common.notYet` | Chưa |
| `common.undo` | Hoàn tác | `common.copy` | Sao chép |
| `common.copied` | Đã sao chép | `common.saved` | Đã lưu |
| `common.readAloud` | Đọc to | `common.stopReading` | Dừng đọc |
| `common.openSettings` | Mở Cài đặt | `common.seeAll` | Xem tất cả |
| `common.empty` | Chưa có | `common.checkAgain` | Kiểm tra lại |
| `common.viewSourceImage` | Xem ảnh gốc | `common.demoData` | Dữ liệu mẫu |
| `common.unsupported` | Chưa hỗ trợ | `common.loading` | Đang xử lý… |
| `common.today` / `common.tomorrow` | Hôm nay / Ngày mai | `common.dateTimeFormat` | {weekday}, {dd/MM} lúc {HH:mm} — e.g. "Thứ Hai, 09/11 lúc 14:00" (24 h, D-003) |

`common.yesDone` ("Đã xong") is used **only** in S08 / S07; it is never placed next to `common.done` ("Xong") (D-250).
## 6. Screens (layout top → bottom, then strings)
### S01 Sign-in
Layout: app icon (96pt) · `display` title · tagline · reason text · spacer · "Tiếp tục với Google" (PrimaryButton with Google "G" mark, 56pt) · legal text with 2 links (open in-app text, D-284). No Apple button in the thesis build (D-283). Loading: button disabled + `ProgressView`.

| Key | vi | Key | vi |
|---|---|---|---|
| `signIn.title` | EasyPhoneK | `signIn.tagline` | Trợ lý giúp bạn dùng điện thoại dễ hơn |
| `signIn.reason` | Bạn cần đăng nhập để dùng trợ lý AI. Lịch, danh bạ và lời nhắc vẫn nằm trên điện thoại của bạn. | `signIn.google` | Tiếp tục với Google |
| `signIn.legal` | Khi tiếp tục, bạn đồng ý với {Điều khoản sử dụng} và {Chính sách quyền riêng tư}. | `signIn.failed` | Đăng nhập không thành công. Bạn thử lại nhé. |
| `signIn.sessionExpired` | Phiên đăng nhập đã hết. Bạn đăng nhập lại nhé. Bản nháp vẫn được giữ. |  |  |
### S02 Home
Layout: toolbar (leading "Lịch sử" `clock.arrow.circlepath`, trailing "Cài đặt" `gearshape`, both icon + text label in simple mode) · `MascotView(.greeting)` ~96pt above the greeting (hidden at AX3+ so the mic stays on screen, P-41) · `display` greeting · `ListeningMic` 120pt centered · mic caption · text field (multi-line, 56pt min) with trailing "Gửi" button (appears only when text is non-empty) · `SecondaryButton` "Chụp ảnh giấy tờ" (`camera`) · quick links row: "Lịch hôm nay", "Lời nhắc", "Địa điểm" (64pt tiles, 2 per row at AX sizes; hidden in simple mode except "Lịch hôm nay", P-40) · section "Việc chưa xong" (drafts in "Cần bạn làm tiếp" or "Đang chờ", D-244; max 3 rows: title + `StateBadge` + relative time, AC5) + "Xem tất cả". Offline/quota banners appear above the mic. Primary buttons on this screen: mic and "Gửi" only.

| Key | vi | Key | vi |
|---|---|---|---|
| `home.greeting` | Bạn cần mình giúp gì? | `home.mic.caption` | Bấm để nói |
| `home.mic.a11y` | Nói yêu cầu | `home.input.placeholder` | Hoặc gõ yêu cầu ở đây |
| `home.send` | Gửi | `home.camera` | Chụp ảnh giấy tờ |
| `home.link.calendar` / `home.link.reminders` / `home.link.places` | Lịch hôm nay / Lời nhắc / Địa điểm | `home.unfinished.title` | Việc chưa xong |
| `home.unfinished.empty` | Không có việc nào đang chờ bạn. | `home.toolbar.history` / `home.toolbar.settings` | Lịch sử / Cài đặt |
| `home.tip.firstRun` | Ví dụ, bạn có thể nói: “Nhắc tôi 8 giờ sáng mai uống thuốc”. | `home.quota.low` | Bạn còn {remaining} lượt AI hôm nay. |
### S03 Conversation
One screen, 5 modes. Top: back button + "Hủy" (discards nothing; draft saved). Content is a simple vertical thread: user bubble (right, `surface`) and assistant bubble (left, `secondaryFill`), `body` font, each with "Đọc to". Assistant bubbles carry a small `MascotView` avatar (P-41) whose pose follows the mode: listening → `listening`, working → `thinking`, follow-up → `asking`, unsupported / parse failed → `sorry`.
1. **Listening:** `ListeningMic` 140pt (stop icon) · "Mình đang nghe…" · live transcript (`fieldValue`, editable after stop) · rotating hint · bottom: PrimaryButton "Dừng" (always visible, AC1). TTS stops when listening starts (AC5).
2. **Transcript ready:** editable text area · PrimaryButton "Gửi" · SecondaryButton "Nói lại". Never auto-send (API §7.4).
3. **Working:** spinner + "Mình đang soạn bản nháp…" · SecondaryButton "Hủy". Then push S04.
4. **Follow-up (needsInfo):** assistant bubble = the ONE question (`followUpQuestion` or `followup.<kind>.<fieldId>`) · mic 120pt + text field · for date questions, chips from `dateCandidates` (each 56pt; tapping a chip fills the field **on device**, no AI call, no quota, D-251) · "Bỏ qua, tôi sẽ sửa sau" → S04. Only a typed/spoken answer calls `/v1/parse`.
5. **Unsupported:** `EmptyState` icon `nosign` · "Chưa hỗ trợ" · `unsupported.message` · PrimaryButton "Về trang chính" · SecondaryButton "Thử cách nói khác". For `recurringEvent` also SecondaryButton `conv.unsupported.oneTimeOffer`. For `bulkAction` (D-280) the secondary is `conv.unsupported.openList` → S11 (calendar) or S12 (reminders).

| Key | vi | Key | vi |
|---|---|---|---|
| `conv.listening.title` | Mình đang nghe… | `conv.listening.stop` | Dừng |
| `conv.listening.hint.1` | Ví dụ: “Gọi cho mẹ” | `conv.listening.hint.2` | Ví dụ: “Nhắn anh Minh là chiều nay em đến muộn” |
| `conv.listening.hint.3` | Ví dụ: “Mai 9 giờ sáng khám răng ở nha khoa An Bình” | `conv.transcript.edit.a11y` | Lời bạn vừa nói, có thể sửa |
| `conv.send` / `conv.speakAgain` | Gửi / Nói lại | `conv.working` | Mình đang soạn bản nháp… |
| `conv.followup.skip` | Bỏ qua, tôi sẽ sửa sau | `conv.speech.unavailable` | Máy chưa nghe được tiếng Việt lúc này. Bạn gõ chữ nhé. |
| `conv.speech.empty` | Mình chưa nghe rõ. Bạn nói lại hoặc gõ chữ nhé. | `conv.unsupported.home` | Về trang chính |
| `conv.unsupported.rephrase` | Thử cách nói khác | `conv.unsupported.oneTimeOffer` | Tạo nhắc một lần cho sáng mai? |
| `conv.parseFailed` | Mình chưa hiểu yêu cầu. Bạn thử nói cách khác nhé. | `conv.unsupported.openList` | Mở danh sách để làm từng việc |
### S04 Review (core screen, spec §5.3)
Layout: nav title = step title (§10.1) · `StepIndicator` if > 1 step · `StateBadge` · optional conflict card · optional banner (error, `approval.mismatch`, offline) · `FieldRow` list in catalog order (DATA_MODEL §4; 🔒 ids rendered as their human row: `contactId` → contact name + photo + masked number, `calendarId` → calendar name, `coordinate` → small map; rows not required for the current `channel`/operation are hidden, DATA_MODEL §4.1) · original input disclosure "Bạn đã nói / gõ: “…”" · bottom bar: PrimaryButton "Xác nhận" · SecondaryButton "Sửa" · SecondaryButton "Hủy" (D-182). Focus order: title → badge → banner → fields → buttons.
- "Xác nhận" disabled while any required field is empty, any ambiguity exists, or the previous linked step is not
  final/`handedOff`/`prepared`; show the reason text under it.
- "Xác nhận" with a capability whose permission is `notDetermined` → S18 explainer first (ARCHITECTURE §5.1 step 0).
- "Sửa" opens S05 for the first `needsReview` field, else the first field (P-37).
- Delete operation: primary becomes destructive "Xác nhận xóa" (`danger`), plus hint; voice "có" not accepted (D-108, P-39).
- Voice mode on: reads `review.tts.<kind>` aloud once; listens for "có"/"đồng ý" (not for delete).
- After "Xác nhận": the bottom bar is replaced by a **result card** for that step (§S04 result strings), never a new screen.

| Key | vi | Key | vi |
|---|---|---|---|
| `review.disabled.missing` | Cần điền ô có dấu “Chưa có” trước khi xác nhận. | `review.disabled.ambiguity` | Cần chọn thông tin được đánh dấu trước khi xác nhận. |
| `review.disabled.previousStep` | Hãy làm xong bước trước rồi xác nhận bước này. | `review.conflict.title` | Trùng giờ với lịch khác |
| `review.conflict.row` | {title} — {time} | `review.conflict.note` | Bạn vẫn có thể tạo lịch này. |
| `review.originalInput` | Bạn đã yêu cầu: “{text}” | `review.delete.confirm` | Xác nhận xóa |
| `review.delete.hint` | Việc xóa cần bạn bấm nút, không xác nhận bằng giọng nói. | `review.editedAfterApproval` | Bạn vừa sửa thông tin, hãy xác nhận lại. |
| `review.tts.calendarEvent` | Mình sẽ tạo lịch {title} vào {dateTime}. Bạn đồng ý không? | `review.tts.reminder` | Mình sẽ nhắc bạn {title} vào {dateTime}. Bạn đồng ý không? |
| `review.tts.call` | Mình sẽ gọi cho {name}. Bạn đồng ý không? | `review.tts.sms` | Tin nhắn gửi {name}: {body}. Bạn đồng ý không? |
| `review.tts.place` | Địa điểm: {name}, {address}. Bạn đồng ý không? |  |  |

Result card (replaces the button bar of the finished step; title `title` font, icon `icon.hero`):

| Key | vi | Key | vi |
|---|---|---|---|
| `result.processing` | Đang thực hiện… | `result.calendarEvent.created` / `.updated` / `.deleted` | Đã tạo lịch hẹn trong Lịch. / Đã sửa lịch hẹn. / Đã xóa lịch hẹn. |
| `result.reminder.created` / `.completed` / `.snoozed` | Đã tạo lời nhắc. / Đã đánh dấu xong. / Đã dời lời nhắc tới {dateTime}. | `result.sms.sent` | Tin nhắn đã được gửi. |
| `result.place.saved` | Đã lưu địa điểm “{label}”. | `result.ocr.confirmed` | Đã lưu thông tin từ ảnh. |
| `result.call.handedOff` | Cần hoàn tất cuộc gọi trong ứng dụng Điện thoại. | `result.directions.handedOff` | Đường đi đã được mở trong {app}. |
| `result.unknown` | Chưa rõ kết quả. Mình sẽ kiểm tra lại khi bạn mở ứng dụng. | `result.markDone` | Tôi đã làm xong |
| `result.failed` | Không thành công. | `result.openInCalendar` / `result.openInReminders` | Mở trong Lịch / Mở trong Lời nhắc |
| `result.nextStep` | Tiếp tục: {stepTitle} | `result.allDone` | Xong rồi! |

Buttons per state (D-250):
- `succeeded` → Primary `result.nextStep` (or `common.done` → S02) + Secondary "Mở trong Lịch" / "Mở trong Lời nhắc".
- `handedOff` → Primary `result.markDone` (`userMarkedDone`) + Secondary `common.later` (stays `handedOff`).
- `unknown` → Primary `result.markDone` + Secondary `common.retry` for calendar/reminder (`retry`, D-243), else `common.later`.
- `failed` → Primary `common.retry` + Secondary `common.cancel` (`userCancelled`, D-243). If `errorCode` is
  `permission.<c>.denied`: Primary `perm.<c>.fallback` (e.g. copy text) + Secondary `result.markDone`; "Hủy" stays in the toolbar.
### S05 Field editor (sheet)
Title = field label. Control by `FieldType`: `text` → `TextField` (`fieldValue`); `longText` → `TextEditor` 160pt min + "Đọc to"; `dateTime` → `DatePicker(.graphical)` for date + `.wheel` for time, with chips "Hôm nay", "Ngày mai"; `date` → graphical only; `durationMinutes` (alert) → choice list (P-35); `bool` → `Toggle` 56pt row; `enumChoice` → radio list rows 64pt with `checkmark`; `address` → text + "Tìm trên bản đồ" (S13 picker); `phone` → number pad. Bottom: PrimaryButton "Lưu" · SecondaryButton "Hủy". Inline validation text in `danger` + icon.

| Key | vi | Key | vi |
|---|---|---|---|
| `editor.clear` | Xóa nội dung | `editor.findOnMap` | Tìm trên bản đồ |
| `editor.invalid.endBeforeStart` | Giờ kết thúc phải sau giờ bắt đầu. | `editor.invalid.past` | Thời gian này đã qua. Bạn chọn thời gian khác nhé. |
| `editor.invalid.tooLong` | Nội dung quá dài (tối đa {max} ký tự). | `editor.invalid.phone` | Số điện thoại chưa đúng. |
### S06 Picker (sheet, D-106 — never auto-pick)
Title = `Ambiguity.question` · rows 72pt: photo/initials 44pt, `title` (`fieldValue`), `subtitle` (masked "•••• 567" or date). No default selection; tapping a row picks and closes (on device, no quota, D-251). Contacts limited access → `ContactAccessButton` row at the bottom. No match → empty state + "Chọn trong danh bạ" (`CNContactPickerViewController` bridge). After picking a contact for a kinship/nickname word, show inline offer `picker.saveNickname` (spec §6.6 AC3).

| Key | vi | Key | vi |
|---|---|---|---|
| `ambiguity.contact.sms` | Bạn muốn nhắn {name} nào? | `ambiguity.contact.call` | Bạn muốn gọi {name} nào? |
| `ambiguity.phoneNumber` | Bạn muốn dùng số nào của {name}? | `ambiguity.date` | Bạn muốn chọn ngày nào? |
| `ambiguity.place` | Bạn muốn chọn địa điểm nào? | `ambiguity.event` | Bạn muốn chọn lịch hẹn nào? |
| `picker.noMatch` | Mình chưa tìm thấy người này, bạn chọn trong danh bạ nhé | `picker.openContacts` | Chọn trong danh bạ |
| `picker.phoneLabel` | {label}: •••• {last3} | `picker.saveNickname` | Lưu “{nickname}” là {contactName} để lần sau mình nhận ra? |
| `picker.saveNickname.yes` / `.no` | Lưu / Không cần |  |  |
### S07 Copy guide (channel not verified, D-162)
Layout: title · status card (`doc.on.doc` + `copy.status`) · message preview (`surface`, `fieldValue`) · numbered steps from `SupportedServices.json` `guideSteps` (each row 56pt, big number circle) · PrimaryButton "Đã xong" · SecondaryButton "Sao chép lại". Shown only **after** "Xác nhận" on S04; the text is copied when the screen opens (step → `handedOff`). No contact permission is needed on this path (D-247).

| Key | vi | Key | vi |
|---|---|---|---|
| `copy.title` | Gửi qua {service} | `copy.status` | Đã sao chép — dán và gửi trong {service} |
| `copy.stepsTitle` | Bạn làm theo các bước sau: | `copy.again` | Sao chép lại |
### S08 Hand-off return prompt (sheet, D-242 — once per hand-off)
Medium detent · icon · question (`title`) · step summary (`body`) · PrimaryButton "Đã xong" · SecondaryButton "Chưa". "Chưa" → toast `handoff.notYet.toast`. Voice "có" = "Đã xong".

| Key | vi | Key | vi |
|---|---|---|---|
| `handoff.call` | Bạn đã gọi xong chưa? | `handoff.directions` | Bạn đã đi tới nơi chưa? |
| `handoff.copyMessage` | Bạn đã gửi tin nhắn trong {service} chưa? | `handoff.ride` / `handoff.food` | Bạn đã đặt xong chưa? (Phase 3) |
| `handoff.notYet.toast` | Việc này vẫn nằm trong “Việc chưa xong”. |  |  |
### S09 Photo capture → OCR
1. **Choose source** (confirmation dialog): "Chụp ảnh" (camera) / "Chọn ảnh có sẵn" (`PhotosPicker`, 1 image) / "Hủy". Tips card above: `ocr.tips`.
2. **Reading:** photo thumbnail + spinner + "Mình đang đọc chữ trong ảnh…" (Vision, then fallback `/v1/ocr`).
3. **Text found:** push S04 with the `ocr` step: `extractedText` row with "Đọc to", then `title`, `dateTime`, `address`, `personName`, `phoneNumber` rows (all `warningBg` + "Xem ảnh gốc"), then `nextAction` radio list. Primary "Tiếp tục" (`common.continue`) is this step's confirm: it emits `userConfirmed` on the `ocr` step (→ `succeeded`, `local:confirmed`) and appends the linked step; Secondary "Chụp lại".
4. **No text / blurry (AC5):** `EmptyState` `doc.text.magnifyingglass` · PrimaryButton "Chụp lại" · Secondary "Chọn ảnh khác".

| Key | vi | Key | vi |
|---|---|---|---|
| `ocr.source.camera` / `ocr.source.library` | Chụp ảnh / Chọn ảnh có sẵn | `ocr.tips` | Đặt giấy trên mặt phẳng, đủ sáng, chụp thẳng và rõ chữ. |
| `ocr.reading` | Mình đang đọc chữ trong ảnh… | `ocr.noText.title` | Mình chưa đọc được chữ trong ảnh |
| `ocr.noText.body` | Ảnh có thể bị mờ, tối hoặc chụp nghiêng. Bạn chụp lại nhé. | `ocr.retake` / `ocr.otherPhoto` | Chụp lại / Chọn ảnh khác |
| `ocr.nextAction.title` | Bạn muốn làm gì với thông tin này? | `ocr.oneImageNote` | Mỗi lần chỉ đọc một ảnh. |
### S10 Source image
Full-screen black background, image fit, the field's `boundingBox` outlined 3pt `warning` + dimmed rest, pinch-zoom. Top: "Đóng". Bottom caption: "Thông tin “{fieldLabel}” được lấy từ vùng này." VoiceOver reads the caption + span text.

| Key | vi | Key | vi |
|---|---|---|---|
| `source.title` | Ảnh gốc | `source.caption` | Thông tin “{fieldLabel}” được lấy từ vùng này. |
| `source.noBox` | Không xác định được vị trí trong ảnh. |  |  |
### S11 Calendar today
Header `display` "Lịch hôm nay" + date (`common.dateTimeFormat` date part). Rows 72pt: time column (`label`), title (`fieldValue`), location (`body`). Conflicting rows show `exclamationmark.triangle` + "Trùng giờ". Tap → detail sheet (fields read-only + Primary "Sửa" + Secondary "Xóa" (danger text) + link "Mở trong Lịch"); "Sửa"/"Xóa" create an update/delete step → S04. Bottom: PrimaryButton "Thêm lịch hẹn" → S03 in typing mode. Recurring event → "Chưa hỗ trợ sửa lịch lặp lại".

| Key | vi | Key | vi |
|---|---|---|---|
| `calendar.title` | Lịch hôm nay | `calendar.empty` | Hôm nay bạn không có lịch hẹn nào. |
| `calendar.add` | Thêm lịch hẹn | `calendar.allDay` | Cả ngày |
| `calendar.conflict` | Trùng giờ | `calendar.delete` | Xóa |
| `calendar.recurringUnsupported` | Chưa hỗ trợ sửa lịch lặp lại. | `calendar.limitedNote` | Chỉ hiện các lịch bạn đã cho phép. |
### S12 Reminders
Sections "Quá hạn", "Sắp tới". Row 72pt: complete circle button (44pt, `circle` → `checkmark.circle.fill`) + title + due time. **Complete = one tap** (D-107) → `reminder/complete` with `completed = true` → toast with "Hoàn tác" (one-tap `completed = false`, D-248). Row menu button `ellipsis.circle` (44pt): "Nhắc lại sau" → snooze sheet (3 rows 64pt) · "Sửa" · "Xóa" → S04. Bottom: PrimaryButton "Thêm lời nhắc" → S03.

| Key | vi | Key | vi |
|---|---|---|---|
| `reminders.title` | Lời nhắc | `reminders.overdue` / `reminders.upcoming` | Quá hạn / Sắp tới |
| `reminders.empty` | Bạn chưa có lời nhắc nào. | `reminders.add` | Thêm lời nhắc |
| `reminders.complete.a11y` | Đánh dấu “{title}” là đã xong | `reminders.completed.toast` | Đã đánh dấu xong |
| `reminders.snooze` | Nhắc lại sau | `reminders.snooze.title` | Nhắc lại lúc nào? |
### S13 Places
Search field (`places.search`) · results list (name + address, 72pt) · selecting shows a map preview card (200pt, `Map` with one marker) with PrimaryButton "Lưu địa điểm" + SecondaryButton "Chỉ đường" · section "Địa điểm đã lưu" (Nhà / Chỗ làm / custom, each with `house`/`briefcase`/`mappin`). Save → S04 `place.create` (label choice row). Directions → S04 `place.open` with the chosen result as destination (D-248).

| Key | vi | Key | vi |
|---|---|---|---|
| `places.title` | Địa điểm | `places.search` | Tìm địa chỉ hoặc tên địa điểm |
| `places.noResults` | Không tìm thấy địa điểm. Bạn thử gõ tên khác nhé. | `places.save` / `places.directions` | Lưu địa điểm / Chỉ đường |
| `places.saved.title` | Địa điểm đã lưu | `places.saved.empty` | Bạn chưa lưu địa điểm nào. Hãy lưu Nhà hoặc Chỗ làm để dùng nhanh hơn. |
| `places.customLabel.placeholder` | Ví dụ: Nhà con gái | `places.locationDenied` | Bạn vẫn tìm được địa chỉ bằng cách gõ tên. |
### S14 History
Grouped list, fixed order (spec §6.10 AC1): "Cần bạn làm tiếp", "Đang chờ", "Đã xong", "Đã hủy". Row 72pt: kind icon + summary (`history.summary`, e.g. "Soạn tin nhắn: anh Minh") + relative time + `StateBadge` of the draft's group step. Tap → S04 at `currentStep` (DATA_MODEL §3.2). Swipe action "Ẩn" (`isArchived`). Multi-step rows show "{done}/{total} bước" (done = closed steps, D-244).

| Key | vi | Key | vi |
|---|---|---|---|
| `history.title` | Lịch sử | `history.group.needsYou` | Cần bạn làm tiếp |
| `history.group.waiting` | Đang chờ | `history.group.done` | Đã xong |
| `history.group.cancelled` | Đã hủy | `history.empty` | Chưa có việc nào. |
| `history.hide` | Ẩn | `history.steps` | {done}/{total} bước |
| `history.time.today` / `.yesterday` | Hôm nay {HH:mm} / Hôm qua {HH:mm} |  |  |
### S15 Settings
`List(.insetGrouped)`, rows 56pt, title `settings.title` = "Cài đặt". Sections in this order; simple mode hides ★ rows (P-40). Format: `key` = vi (behavior).

| Section | Rows |
|---|---|
| `settings.account` = Tài khoản | `settings.plan.free` / `.premium` = Gói: Miễn phí / Gói: Premium (`/v1/me`) · `settings.quota` = Lượt AI còn lại hôm nay: {remaining}/{limit} (AC7) · `settings.quota.reset` = Lượt mới có lúc {time} · `settings.upgrade` = Nâng cấp Premium (→ S16) / `settings.manageSub` = Quản lý gói (`showManageSubscriptions`) |
| `settings.voice` = Giọng nói | `settings.voice.enabled` = Đọc to câu trả lời (toggle) · `settings.voice.rate` = Tốc độ đọc (slider, ends `.slow` = Chậm / `.fast` = Nhanh) · `settings.voice.test` = Nghe thử (speaks `settings.voice.sample` = Xin chào, mình là EasyPhoneK.) |
| `settings.display` = Hiển thị | `settings.textSize` = Cỡ chữ (live preview + `settings.textSize.note` = Đổi cỡ chữ trong Cài đặt iPhone > Màn hình & Độ sáng > Cỡ chữ.) · `settings.simpleMode` = Chế độ đơn giản (toggle; footer `settings.simpleMode.note` = Ẩn bớt các tùy chọn nâng cao.) · `settings.pet` = Hiện bạn Khoai (toggle, on by default; footer `settings.pet.note` = Khoai chỉ là nhân vật hướng dẫn, tắt đi app vẫn chạy như cũ.) (P-41) |
| `settings.memory` = Ghi nhớ | `settings.nicknames` = Tên gọi thân mật (rows "mẹ → Nguyễn Thị Lan", swipe "Xóa"; `settings.nicknames.empty` = Chưa có tên gọi nào.) · `settings.savedPlaces` = Địa điểm đã lưu (→ S13) |
| ★ `settings.advanced` = Nâng cao | `settings.snoozeHour` = Giờ của “sáng mai” (picker 5–11, "{hour} giờ") · `settings.mapsApp` = Mở chỉ đường bằng · `settings.permissions` = Quyền truy cập (one row per capability + status §10.4 + "Mở Cài đặt") |
| `settings.connections` = Kết nối | `settings.gmail.soon` = Gmail — sắp có (disabled, D-150) |
| `settings.data` = Dữ liệu | `settings.clearHistory` = Xóa lịch sử · `settings.clearMemory` = Xóa dữ liệu ghi nhớ (both → S20) |
| `settings.about` = Thông tin | `settings.aiDisclosure` = Yêu cầu AI của bạn được xử lý bởi một nhà cung cấp AI bên thứ ba (OpenAI). Danh bạ và lịch được xử lý trên điện thoại. (D-187) · `settings.privacy` = Chính sách quyền riêng tư · `settings.terms` = Điều khoản sử dụng · `settings.version` = Phiên bản {version} (`caption`) |
| (no header) | `settings.signOut` = Đăng xuất · `settings.deleteAccount` = Xóa tài khoản (`danger` text) — both → S20 |
### S16 Paywall (sheet, D-089)
Layout: close button "Để sau" · `display` title · subtitle · optional context banner (from 402) · 3 benefit rows (`checkmark.circle`) · 2 plan cards (radio, 88pt, price from StoreKit `displayPrice`, yearly shows period) · renewal text · PrimaryButton "Đăng ký" · SecondaryButton "Để sau" · links "Khôi phục giao dịch", Terms, Privacy. Never show a price that StoreKit did not return. Benefits must stay true for MVP (no promised features).

| Key | vi | Key | vi |
|---|---|---|---|
| `paywall.title` | EasyPhoneK Premium | `paywall.subtitle` | Dùng trợ lý AI thoải mái hơn mỗi ngày |
| `paywall.context.quota` | Bạn đã dùng hết {limit} lượt miễn phí hôm nay. Lượt mới có lúc {time}. | `paywall.benefit.quota` | Tới {premiumLimit} lượt AI mỗi ngày |
| `paywall.benefit.all` | Dùng giọng nói, đọc chữ từ ảnh và soạn tin không lo hết lượt sớm | `paywall.benefit.same` | Dữ liệu của bạn vẫn được bảo vệ như gói miễn phí |
| `paywall.plan.monthly` | Gói tháng — {price}/tháng | `paywall.plan.yearly` | Gói năm — {price}/năm |
| `paywall.renewal` | Tự động gia hạn. Bạn có thể hủy bất cứ lúc nào trong Cài đặt iPhone, chậm nhất 24 giờ trước khi hết kỳ. | `paywall.subscribe` | Đăng ký |
| `paywall.restore` | Khôi phục giao dịch | `paywall.restore.none` | Không tìm thấy giao dịch nào để khôi phục. |
| `paywall.pending` | Giao dịch đang chờ duyệt. Mình sẽ cập nhật khi được duyệt. | `paywall.success` | Bạn đã là thành viên Premium. Cảm ơn bạn! |
| `paywall.productsUnavailable` | Chưa tải được các gói. Bạn thử lại sau nhé. |  |  |
### S17 Quota reached — Premium (sheet, D-241)
Icon `hourglass` · title · body · note on device features · PrimaryButton "Đã hiểu".

| Key | vi | Key | vi |
|---|---|---|---|
| `quota.premium.title` | Bạn đã dùng hết lượt hôm nay | `quota.premium.body` | Lượt mới có lúc {time}, {date}. |
| `quota.stillWorks` | Bạn vẫn xem lịch, gọi người đã lưu và xem lịch sử được. | `quota.ok` | Đã hiểu |
### S18 Permission explainer / denied (D-185)
Explainer (shown before "Xác nhận" executes when status is `notDetermined`): icon `icon.hero` · title · body (why + "chỉ trên điện thoại") · PrimaryButton "Cho phép" (then the system alert) · SecondaryButton "Để sau". Denied/restricted: title `perm.denied.title` · what still works · PrimaryButton "Mở Cài đặt" · SecondaryButton = fallback (copy text / type / choose photo) or "Để sau".

| Capability | `perm.<c>.title` | `perm.<c>.body` | `perm.<c>.fallback` (denied) |
|---|---|---|---|
| calendar | Cho phép dùng Lịch | Để mình tạo và xem lịch hẹn giúp bạn. Lịch chỉ được đọc trên điện thoại. | Sao chép thông tin lịch hẹn |
| reminders | Cho phép dùng Lời nhắc | Để mình tạo lời nhắc đúng giờ cho bạn. | Sao chép nội dung nhắc |
| contacts | Cho phép dùng Danh bạ | Để mình tìm đúng người khi bạn muốn gọi hoặc nhắn tin. Danh bạ không được gửi đi đâu. | Nhập số điện thoại |
| microphone | Cho phép dùng micro | Để bạn nói yêu cầu thay vì gõ chữ. | Gõ chữ |
| speech | Cho phép nhận dạng giọng nói | Để mình hiểu lời bạn nói bằng tiếng Việt. | Gõ chữ |
| camera | Cho phép dùng camera | Để chụp giấy hẹn, tờ ghi chú và đọc chữ giúp bạn. | Chọn ảnh có sẵn |
| photos | Cho phép chọn ảnh | Để bạn chọn ảnh giấy tờ có sẵn trong máy. | Chụp ảnh |
| location | Cho phép dùng vị trí | Để tìm địa điểm gần bạn hơn. | Gõ tên địa điểm |

| Key | vi | Key | vi |
|---|---|---|---|
| `perm.allow` | Cho phép | `perm.denied.title` | {feature} chưa được cho phép |
| `perm.denied.body` | Bạn có thể bật lại trong Cài đặt iPhone. Các tính năng khác vẫn dùng được. | `perm.limited.contacts` | Bạn đang cho phép một số liên hệ. Thêm người bằng nút bên dưới. |
| `perm.writeOnly.calendar` | Mình chỉ được thêm lịch, không xem được lịch có sẵn nên không kiểm tra trùng giờ. |  |  |

`Info.plist` usage descriptions (D-186, `InfoPlist.xcstrings`, vi):

| Key | vi | Key | vi |
|---|---|---|---|
| `NSMicrophoneUsageDescription` | EasyPhoneK dùng micro để nghe yêu cầu bạn nói. | `NSSpeechRecognitionUsageDescription` | EasyPhoneK chuyển lời bạn nói thành chữ để hiểu yêu cầu. |
| `NSCameraUsageDescription` | EasyPhoneK dùng camera để chụp giấy tờ và đọc chữ giúp bạn. | `NSPhotoLibraryUsageDescription` | EasyPhoneK đọc ảnh bạn chọn để lấy thông tin như ngày hẹn, địa chỉ. |
| `NSCalendarsFullAccessUsageDescription` | EasyPhoneK xem và tạo lịch hẹn theo yêu cầu của bạn. Lịch chỉ được xử lý trên điện thoại. | `NSRemindersFullAccessUsageDescription` | EasyPhoneK tạo và quản lý lời nhắc theo yêu cầu của bạn. |
| `NSContactsUsageDescription` | EasyPhoneK tìm người trong danh bạ để gọi hoặc nhắn tin. Danh bạ không được gửi lên máy chủ. | `NSLocationWhenInUseUsageDescription` | EasyPhoneK dùng vị trí để tìm địa điểm gần bạn. |
### S19 Update required (426, blocking)
| Key | vi | Key | vi |
|---|---|---|---|
| `update.title` | Cần cập nhật ứng dụng | `update.body` | Phiên bản này đã cũ. Hãy cập nhật EasyPhoneK (tối thiểu {minVersion}) để tiếp tục dùng. |
| `update.cta` | Mở App Store |  |  |
### S20 Destructive confirms (`ConfirmSheet`, primary = destructive)
| Key | vi | Key | vi |
|---|---|---|---|
| `confirm.deleteAccount.title` | Xóa tài khoản? | `confirm.deleteAccount.body` | Toàn bộ dữ liệu của bạn trên máy chủ và trên điện thoại này sẽ bị xóa. Việc này không hoàn tác được. |
| `confirm.deleteAccount.subNote` | Xóa tài khoản không tự hủy gói Premium. Hãy hủy trong Cài đặt iPhone > tên của bạn > Đăng ký. | `confirm.deleteAccount.yes` / `.no` | Xóa tài khoản / Giữ tài khoản |
| `confirm.deleteAccount.progress` / `.done` | Đang xóa… / Đã xóa tài khoản. | `confirm.clearHistory.title` / `.body` | Xóa lịch sử? / Các việc đã xong và đã hủy sẽ bị xóa. Việc chưa xong vẫn được giữ. |
| `confirm.clearMemory.title` / `.body` | Xóa dữ liệu ghi nhớ? / Tên gọi thân mật và địa điểm đã lưu sẽ bị xóa. | `confirm.signOut.title` / `.body` | Đăng xuất? / Bản nháp trên điện thoại vẫn được giữ. |
| `confirm.delete` / `confirm.signOut.yes` | Xóa / Đăng xuất |  |  |

"Xóa lịch sử" removes only drafts whose steps are all closed (`succeeded`, `cancelled`, `userMarkedDone`, D-244).
## 7. Entry points (no screen of their own, D-170 – D-172)
| Item | Key | vi |
|---|---|---|
| App Shortcut phrases (iOS 18.4+ vi; en fallback, D-012) | `shortcut.phrase.1/2/3/4` | “Ê Khoai”, “Khoai”, “Mở EasyPhoneK”, “Nói với EasyPhoneK” · en: “Open EasyPhoneK”, “Talk to EasyPhoneK” — “Khoai” = `INAlternativeAppNames` entry, phrases written `"Ê \(.applicationName)"` / `"\(.applicationName)"` (D-288); bare “Khoai” kept only if Xcode/Siri accept it on device (1E.2) |
| `StartListeningIntent` title / description | `intent.listen.title` / `.desc` | Bắt đầu nghe / Mở EasyPhoneK và nghe yêu cầu của bạn |
| Control Center control | `control.listen` | Nói với EasyPhoneK |
| Home widget (small/medium) | `widget.title` / `widget.cta` | EasyPhoneK / Bấm để nói |
| Lock Screen widget (circular) | `widget.lock.a11y` | Nói với EasyPhoneK |
| Medium widget extra line | `widget.unfinished` | {count} việc chưa xong (count per D-244) |
## 8. Global banners, toasts, errors (`error.<code>`, ARCHITECTURE §9.2, code scheme D-249)
| Key | vi | Shown as | Key | vi | Shown as |
|---|---|---|---|---|---|
| `error.network.offline` | Không có mạng — bản nháp đã được lưu | Banner + "Thử lại" | `error.unauthorized` | Phiên đăng nhập đã hết. Bạn đăng nhập lại nhé. | S01 |
| `error.quota_exceeded` | Bạn đã dùng hết lượt hôm nay. | S16 / S17 | `error.billing_account_mismatch` | Giao dịch thuộc tài khoản khác. | Banner (S16) |
| `error.billing_invalid` | Không xác minh được giao dịch. | Banner (S16) | `error.not_found` / `error.invalid_input` | Có lỗi, bản nháp đã được lưu. | Banner |
| `error.payload_too_large` | Ảnh hoặc nội dung quá lớn. Bạn thử ảnh khác hoặc nội dung ngắn hơn nhé. | Banner | `error.client_outdated` | Cần cập nhật ứng dụng. | S19 |
| `error.rate_limited` | Giọng nói tạm thời chưa dùng được. Bạn gõ chữ nhé. | Banner, keyboard focus | `error.internal` / `error.upstream_error` | Có lỗi, bản nháp đã được lưu. | Banner + "Thử lại" |
| `error.llm_invalid_output` | Mình chưa hiểu yêu cầu. Bạn thử lại nhé. | Banner + "Thử lại" | `error.spend_cap` | Dịch vụ AI tạm dừng. Các tính năng khác vẫn dùng được. | Banner |
| `error.approval.mismatch` | Thông tin đã thay đổi, vui lòng xác nhận lại | S04 banner | `error.permission.<capability>.denied` | Ứng dụng chưa được phép dùng {feature}. | S18 denied + S04 card |
| `error.eventkit.saveFailed` | Không lưu được vào {app}. Bạn thử lại nhé. | S04 result | `error.messages.cannotSend` | Điện thoại này chưa gửi được tin nhắn. Bạn có thể sao chép nội dung. | S04 + "Sao chép" |
| `error.speech.vi.unavailable` | Máy chưa nghe được tiếng Việt lúc này. Bạn gõ chữ nhé. | S03 | `error.generic` | Có lỗi xảy ra. Bạn thử lại nhé. | fallback for unknown codes (then server `message`) |

`<capability>` ∈ `calendar, reminders, contacts, microphone, speech, camera, photos, location` (one key each).
## 9. Accessibility checklist per screen (D-180 – D-183)
- Every icon-only control has `accessibilityLabel` from the `*.a11y` key or its visible text; decorative images hidden.
- `FieldRow` VoiceOver = "{label}, {value or Chưa có}{, cần kiểm tra lại}" + hint "Bấm hai lần để sửa".
- `StateBadge` is one element: "Trạng thái: {state label}". Picker rows: "{title}, {subtitle}".
- Mic: label `home.mic.a11y`, value "Đang nghe" while listening, `.startsMediaSession` trait.
- After navigation to S04 and after each result card, move focus to the title (`@AccessibilityFocusState`).
- Test at AX5 + VoiceOver + Increase Contrast + Reduce Motion + Dark mode for S02, S03, S04, S06, S08, S16.
- Voice is never required: every S03 mode has a text path; S04/S08 work by taps alone.
- Mascot (P-41): VoiceOver skips it; Reduce Motion → no animation; it never covers or replaces a button and never signals a result on its own.
## 10. String catalog (non-screen keys)
### 10.1 Step titles `step.<kind>.<operation>` (S04 title, History summary)
- calendarEvent: `create` Tạo lịch hẹn · `update` Sửa lịch hẹn · `delete` Xóa lịch hẹn
- reminder: `create` Tạo lời nhắc · `update` Sửa lời nhắc · `delete` Xóa lời nhắc · `complete` Đánh dấu đã xong · `snooze` Nhắc lại sau
- call `open` Gọi điện · sms `open` Soạn tin nhắn · place `create` Lưu địa điểm · place `open` Chỉ đường · ocr `create` Kiểm tra thông tin từ ảnh
- `history.summary` = {stepTitle}: {mainValue} (e.g. "Soạn tin nhắn: anh Minh")
### 10.2 Field labels `field.<kind>.<id>` (DATA_MODEL §4)
| Kind | id → vi |
|---|---|
| calendarEvent | `title` Tên lịch hẹn · `startDate` Bắt đầu · `endDate` Kết thúc · `allDay` Cả ngày · `location` Địa điểm · `notes` Ghi chú · `alertMinutesBefore` Nhắc trước · `calendarId` Lịch |
| reminder | `title` Việc cần nhắc · `dueDate` Thời gian nhắc · `notes` Ghi chú · `snoozeOption` Nhắc lại lúc · `completed` Đã xong |
| call | `recipientName` Gọi cho · `contactId` Người trong danh bạ · `phoneNumber` Số điện thoại |
| sms | `recipientName` Gửi cho · `contactId` Người trong danh bạ · `phoneNumber` Số điện thoại · `body` Nội dung tin nhắn · `channel` Gửi qua |
| place | `query` Tìm địa điểm · `name` Tên địa điểm · `address` Địa chỉ · `coordinate` Vị trí trên bản đồ · `label` Lưu là · `customLabel` Tên gọi riêng · `mapsApp` Mở bằng |
| ocr | `extractedText` Chữ đọc được · `title` Tên lịch hẹn · `dateTime` Ngày giờ · `address` Địa chỉ · `personName` Người liên hệ · `phoneNumber` Số điện thoại · `nextAction` Bước tiếp theo |
### 10.3 Option labels `option.<fieldId>.<value>`
| Field | value → vi |
|---|---|
| `snoozeOption` | `min15` 15 phút nữa · `hour1` 1 tiếng nữa · `tomorrowMorning` Sáng mai lúc {hour} giờ |
| `label` | `home` Nhà · `work` Chỗ làm · `custom` Tên khác |
| `mapsApp` | `appleMaps` Bản đồ của Apple · `googleMaps` Google Maps |
| `channel` | `sms` Tin nhắn (SMS/iMessage) · `zalo` Zalo |
| `nextAction` | `calendarEvent` Tạo lịch hẹn · `reminder` Tạo lời nhắc · `copyContactInfo` Sao chép tên và số điện thoại · `ride` Chuẩn bị gọi xe (Phase 3) |
| `alertMinutesBefore` (P-35) | `0` Đúng giờ · `15` Trước 15 phút · `60` Trước 1 tiếng · `1440` Trước 1 ngày |
| `allDay`, `completed` | `true` Có · `false` Không |
### 10.4 Follow-up questions `followup.<kind>.<fieldId>` and permission status
| Key | vi | Key | vi |
|---|---|---|---|
| `followup.calendarEvent.title` | Bạn muốn đặt tên lịch hẹn là gì? | `followup.calendarEvent.startDate` | Lịch hẹn vào ngày nào, mấy giờ? |
| `followup.reminder.title` | Bạn muốn được nhắc việc gì? | `followup.reminder.dueDate` | Bạn muốn được nhắc lúc mấy giờ? |
| `followup.call.recipientName` | Bạn muốn gọi cho ai? | `followup.sms.recipientName` | Bạn muốn nhắn cho ai? |
| `followup.sms.body` | Bạn muốn nhắn nội dung gì? | `followup.place.query` | Bạn muốn tìm địa điểm nào? |
| `followup.generic` | Bạn cho mình biết thêm {fieldLabel} nhé? | `permStatus.granted` / `.limited` / `.writeOnly` | Đã cho phép / Cho phép một phần / Chỉ được thêm mới |
| `permStatus.denied` / `.restricted` / `.notDetermined` | Đã từ chối / Bị giới hạn bởi thiết bị / Chưa hỏi |  |  |

State labels: use `state.<raw>` exactly as `DATA_MODEL.md` §8 (`{service}`/`{app}` args = service name or "Điện thoại", "Bản đồ", "Zalo"). Hand-off notes (`handoffNote`): `handoff.note.call` = "Cần hoàn tất cuộc gọi", `handoff.note.copy` = "Đã sao chép — dán và gửi trong {service}", `handoff.note.directions` = "Cần xem đường đi trong {app}".
## 11. Build checklist for this file
- [ ] `Tokens.swift` + asset catalog colors match §1; a unit test computes contrast for every §1.1 text pair (≥ 4.5).
- [ ] Every key in §5–§10 exists in `Localizable.xcstrings` / `InfoPlist.xcstrings` (`vi` filled); a test scans Swift sources for string literals inside `Text("…")` and fails on any non-key literal.
- [ ] Every `error.<code>` from API_CONTRACT §3.2 and ARCHITECTURE §9.2 has a key in §8.
- [ ] Screens S01–S20 each have a `#Preview` (light, dark, AX5) using mocks and the "Dữ liệu mẫu" badge.
- [ ] XCUITest flows 1 & 2 use the accessibility identifiers `screen.<id>` (e.g. `screen.S04`) and button keys as ids.
## 12. Proposals — approved by the owner as D-266 – D-275 (`DECISIONS.md` §12.4)
| ID | Proposal | Why |
|---|---|---|
| P-31 | Add `Route.calendarToday` and `Route.reminders` to ARCHITECTURE §2.2 | spec §6.4 AC1 / §6.5 need list screens; the enum lacks them |
| P-32 | Custom color tokens (§1.1) instead of system colors | system blue fails 4.5:1 for body text (D-183) |
| P-33 | Text floor `.callout`; field values and buttons use `.title3` | elderly users; still fully Dynamic Type |
| P-34 | Voice: app = "mình", user = "bạn" in all strings | matches AI_PROMPTS examples; warm, plain |
| P-35 | `alertMinutesBefore` choices 0 / 15 / 60 / 1440 (+ keep any AI value) | a short list beats a number field |
| P-36 | No onboarding carousel; first run = S01 → S02 with `home.tip.firstRun` | fewer screens for weak users |
| P-37 | "Sửa" opens the editor for the first field needing review, else the first field | gives the secondary button a clear action |
| P-38 | Key scheme `<screen>.<element>`, `common.*`, `step.*`, `field.*`, `option.*`, `followup.*`, `error.*` | predictable for agent + translators |
| P-39 | Delete step: primary label "Xác nhận xóa" in `danger` style | D-108 tap-only delete must look different |
| P-40 | Simple mode hides Home quick links (except "Lịch hôm nay") and Settings ★ rows | makes "Chế độ đơn giản" (spec §9) concrete |

**P-41 — guide mascot "Khoai"** (owner, 2026-11-09 → D-289). Art: owner-supplied, owner holds the rights; transparent PNG ≥ 1024 px or PDF vector, one image per pose (`mascot.greeting`, `.listening`, `.thinking`, `.asking`, `.happy`, `.sorry`; optional `mascot.blink`, `mascot.talk` frames). Missing art when built (1B.16) → SF Symbol placeholder + `// TODO(spec): mascot art`. Placement: S02 (above the greeting), S03 (avatar of assistant bubbles); later S04 may show `happy` **only** on a `succeeded` step with evidence — never on `handedOff` / `prepared` / `unknown` (D-102, D-124). Never on S16, S17, S19, S20. No new dialogue keys: existing bubble / title text speaks for Khoai; TTS unchanged. Toggle `settings.pet` (S15). Why: a friendly face makes the assistant less intimidating for elderly users and gives the thesis demo a clear identity tied to the "Ê Khoai" call phrase (D-288).
