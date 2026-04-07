/** Top-of-funnel questions for macOS dictation, Obsidian, and VoiceInsert (English for search). */
export const faqItems: { question: string; answer: string }[] = [
  {
    question: "What is VoiceInsert?",
    answer:
      "VoiceInsert is a macOS menu bar app for hold-to-talk dictation. You hold a keyboard shortcut, speak, and release; transcribed text is inserted into the app that already has focus (Safari, Slack, IDEs, Obsidian, Notes, etc.). A second optional shortcut can save voice notes into an Obsidian vault as Markdown under Voice Captures folders.",
  },
  {
    question: "How does hold-to-talk dictation work on Mac?",
    answer:
      "You choose a global shortcut in VoiceInsert settings. While you hold it, the app records from the microphone and runs on-device speech recognition. When you release, it finishes recognition and inserts the text into the focused field (via paste, typing, or accessibility-assisted insertion depending on the target app).",
  },
  {
    question: "Is VoiceInsert the same as Apple Dictation?",
    answer:
      "No. Apple’s Dictation (Control key twice or Fn key workflows) is built into macOS. VoiceInsert is a separate app focused on a dedicated hold-to-talk shortcut, a small floating control, Obsidian filing, and consistent behavior across many third-party apps. Both can use Apple’s speech recognition stack on the device.",
  },
  {
    question: "Does VoiceInsert send my voice to the cloud?",
    answer:
      "Dictation uses Apple’s Speech recognition on your Mac; audio is not sent to a custom third-party speech API for transcription. You still grant Microphone and Speech Recognition permissions to VoiceInsert like any dictation tool. Official builds from this site do not require an online license check unless a maintainer ships a custom build with billing enabled.",
  },
  {
    question: "Which macOS version does VoiceInsert support?",
    answer:
      "VoiceInsert targets macOS 13 (Ventura) and later. It runs on Apple Silicon and Intel. Download the release ZIP from this site (Download for Mac); a copy may also appear on the public GitHub Releases page. If Gatekeeper blocks the app, use Control-click → Open once.",
  },
  {
    question: "Can I dictate into Cursor, VS Code, or other IDEs?",
    answer:
      "Yes, when the editor’s input has focus, VoiceInsert can insert into that field like any other macOS app. Reliability improves with Accessibility permission enabled so the app can paste or type into complex Electron or web-based inputs.",
  },
  {
    question: "How do I dictate into a browser (Chrome, Safari, Arc)?",
    answer:
      "Click in the text field so it has focus, then hold your VoiceInsert shortcut and speak. Grant Accessibility if the page uses a rich editor or shadow DOM that blocks simple paste; Input Monitoring is required so the global shortcut works while another app is frontmost.",
  },
  {
    question: "What is Obsidian voice capture in VoiceInsert?",
    answer:
      "You can bind a second shortcut to save spoken notes directly into an Obsidian vault. VoiceInsert creates or uses Voice Captures folders (Ideas, Tasks, Meetings, Journal, Notes, Inbox) and writes Markdown files based on simple voice cues in your phrase.",
  },
  {
    question: "What permissions does VoiceInsert need?",
    answer:
      "Typically Microphone, Speech Recognition, Accessibility (recommended for reliable insertion into other apps), and Input Monitoring (for global shortcuts). The app explains each during setup. Without Input Monitoring, the floating on-screen hold button may still work in some setups.",
  },
  {
    question: "Why won’t my global shortcut work in other apps?",
    answer:
      "On recent macOS versions, VoiceInsert needs Input Monitoring permission and a working global event tap. If permission was granted while the app was already running, try Refresh in settings or relaunch once. Some keys still leak to the front app depending on system policy.",
  },
  {
    question: "Is VoiceInsert free or paid?",
    answer:
      "The Mac app distributed from this site is free: download the ZIP, install, and use dictation with no account or token. If the maintainer adds an optional “buy me a coffee” or similar link on the site, that is voluntary support only—not required to run the app.",
  },
  {
    question: "What languages does VoiceInsert support for dictation?",
    answer:
      "Recognition follows Apple’s installed dictation languages (e.g. English US, Russian). Choose the language in VoiceInsert settings and install the matching language pack under System Settings → Keyboard → Dictation if words are missing or misrecognized.",
  },
  {
    question: "Can I use VoiceInsert offline?",
    answer:
      "On-device recognition works without sending audio to a cloud ASR provider. Some Apple language models may still download or update when online. Pure offline behavior depends on what is already installed for Speech on your Mac.",
  },
  {
    question: "How is VoiceInsert different from Dragon NaturallySpeaking on Mac?",
    answer:
      "Dragon for Mac was discontinued years ago. VoiceInsert is a modern, lightweight hold-to-talk utility using Apple’s speech stack, not a full Dragon replacement with custom vocab training. It fits developers and writers who want fast global dictation into any app.",
  },
  {
    question: "Does VoiceInsert work with Microsoft Word or Google Docs?",
    answer:
      "Yes, when the document field is focused. Complex web editors may need Accessibility enabled. If insertion fails, try the same field with a simpler native app to confirm permissions.",
  },
  {
    question: "What is push-to-talk or PTT dictation?",
    answer:
      "Push-to-talk means the microphone and recognition run only while you hold a key or button—like a walkie-talkie. VoiceInsert implements that pattern so you do not leave dictation always-on and you control exactly when capture starts and stops.",
  },
  {
    question: "Where can I download VoiceInsert?",
    answer:
      "Use the Download for Mac link on this site — the ZIP is hosted on the same origin as the homepage. A copy may also appear on the public GitHub Releases page. Unzip, move VoiceInsert.app to Applications, and launch once (Gatekeeper: Control-click → Open if needed).",
  },
  {
    question: "Is VoiceInsert safe? Is the source code public?",
    answer:
      "Treat it like any menu-bar utility that uses Accessibility: only install builds from sources you trust (this site and the linked public GitHub Releases). The public GitHub repo hosts releases and announcements; whether full application source is published is up to the maintainer.",
  },
  {
    question: "Why does Gatekeeper block VoiceInsert?",
    answer:
      "Unsigned or ad hoc signed builds are common for indie Mac tools. macOS may show an unidentified developer warning. Use Control-click → Open the first time, or allow the app under Privacy & Security, or build and sign locally with your own Apple Developer workflow.",
  },
  {
    question: "How can I support VoiceInsert?",
    answer:
      "The app is free. If the site shows a Support or donation link (e.g. Buy Me a Coffee, Ko-fi), you can use it to tip the maintainer; it does not unlock extra features in the distributed build.",
  },
];
