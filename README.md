# DenCam

A paid iOS app for filming terrarium animals at night. DenCam uses motion detection to automatically record when your animals are active, while aggressively managing battery, heat, and storage for overnight sessions.

## Core Features
- Motion-triggered recording with configurable post-motion tail
- User-defined Region of Interest (ROI) with draggable corner handles
- Screen auto-dims to zero brightness after phone stillness detected
- Thermal state monitoring with graceful recording pause
- User-defined storage quota
- Saves video to standard iOS Photos library

## Roadmap
- Sensitivity slider for motion threshold tuning
- Scheduled recording window (arm between time A and time B)
- Lock exposure and white balance for stable IR footage
- Morning summary local notification
- Motion object bounding box overlay (toggleable)

## Tech Stack
- Language: Swift
- UI: UIKit
- Camera: AVFoundation
- Minimum iOS: 16.0

## Development
This project is developed collaboratively with Claude (Anthropic). See `CLAUDE.md` for session boot instructions and `DEVLOG.md` for milestone history.

## App Store
Intended for sale on the Apple App Store. Apple Developer account required for distribution.
