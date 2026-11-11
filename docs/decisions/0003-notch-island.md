# 0003: The notch island is the primary interface

**Decision.** On Macs with a notch, Utter's UI is a "dynamic island": idle, it's exactly the notch (invisible, covers nothing); it grows downward on hover or during a session. Macs without a notch get a draggable floating pill automatically. There's no setting to choose.

**Why.** It's always available without taking screen space or focus, and it's a recognizable home for a voice assistant. Supporting two styles as user options doubled the UI to maintain.

**Details that matter.**
- The island must never draw into the area beside the camera; earlier versions with indicators there looked wrong.
- Hover is detected by pointer position just below the notch, because the pointer disappears under the notch itself.
- During a dictation the island keeps one size from listening to "Inserted N words".
