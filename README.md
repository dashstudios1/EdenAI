# EdenAI
# EdenAI 🤖✨

An iOS AI companion app that turns your iPhone or iPad into a mini interactive desktop robot inspired by Amazon Astro.

## Features
* **Expressive Animated Eyes:** Dynamic SwiftUI eye states including *Idle* (with natural blinking), *Sleeping* (with floating `zZz` particles), *Surprised*, *Thinking*, and *Happy*.
* **Hands-Free Wake Word Detection:** Uses Apple's Speech Recognition (`SFSpeechRecognizer`) and `AVAudioEngine` to listen for `"Hey Eden"` or `"Eden"`.
* **Voice Responses:** Speaks back using built-in text-to-speech (`AVSpeechSynthesizer`) with custom pitch and rate.
* **Touch-to-Wake & Auto-Sleep:** Automatically drifts to sleep after 5 seconds of inactivity and wakes up with a chime when tapped or called.

## Requirements
* iOS 16.0 or later
* Microphone & Speech Recognition permissions enabled

## How to Build & Install (IPA)
This repository uses **GitHub Actions** and **XcodeGen** to automatically compile an unsigned `.ipa` in the cloud:

1. Go to the **Actions** tab in this repository and select the latest green **Build Unsigned IPA** workflow run.
2. Scroll down to **Artifacts** and download **`EdenAI-Unsigned-IPA`**.
3. Unzip the file to extract **`EdenAI.ipa`**.
4. Sideload `EdenAI.ipa` onto your iPhone or iPad using **Sideloadly**, **AltStore**, **SideStore**, or **TrollStore**.

## Voice Commands
Try saying:
* *"Hey Eden, turn on the lights"*
* *"Hey Eden, check the thermostat"*
* *"Hey Eden, tell me a joke"*
