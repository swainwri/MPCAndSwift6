## MPCAndSwift6

A practical MultipeerConnectivity reference project built with Swift 6 and modern concurrency

This repository demonstrates a working, real-device MultipeerConnectivity (MPC) setup using Swift 6, with a clear separation between UI, session management, and Apple’s delegate-based APIs.

It exists because converting legacy MPC code to Swift 6 is not straightforward, and many examples online either:
-    rely on outdated concurrency rules
-    ignore Swift 6 actor isolation
-    break when run on real devices
-   or silently fail without explanation

This project was built from the ground up after repeated failures trying to retrofit Swift 6 concurrency onto an older MPC architecture.

⸻

### What This Project Does

-    Discovers nearby peers
-    Displays peers in a UITableView
-    Sends and receives invitations
-    Accepts / rejects connections via UI
-    Tracks per-peer connection state
-    Sends and receives messages
-    Sends and receives small files
-    Shows per-peer file transfer progress
-    Runs on real iOS devices (not simulators)

Important: MultipeerConnectivity does work on a Simulator.
This project is designed to be tested on two physical iOS devices.

### Architecture Overview

Apple’s MultipeerConnectivity API is:
-    delegate-driven
-    Objective-C based
-    not concurrency-aware

Swift 6 is:
-    strict about actor isolation
-    strict about Sendable
-    unforgiving of cross-actor UI access

## The solution used here

This project uses three layers:

### MPCActor

An actor that owns all MPC objects:
-    MCSession
-   MCNearbyServiceBrowser
-    MCNearbyServiceAdvertiser

It is responsible for:
-    starting/stopping MPC
-    sending messages
-    sending files
-    exposing async-safe access to session state

No UIKit code should live here.

### Delegate Bridges (critical)

Because MPC delegates cannot live inside actors, each delegate is bridged:
-    MCSessionDelegateBridge
-    MPCBrowserDelegateBridge
-    MPCAdvertiserDelegateBridge

These are:
-    NSObject subclasses
-    isolated to @MainActor
-    forward events safely into MPCActor using Task {}

This avoids:
-    Swift 6 isolation errors
-    crashes
-    undefined delegate behavior

###  PeerSessionManager

A UI-facing coordinator that:
-    tracks peers and connection state
-    exposes callbacks like:
         onPeersUpdated
        onPeerStateChanged
         onInvitationReceived
-     feeds data into the UITableView
-   sures all UI updates occur on the main actor

### Why This Repo Exists

During development, these were encountered:
-    Swift 6 compile-time isolation failures
-    Delegates that compiled but never fired
-    Invitations sent but never received
-    Sessions connecting but immediately dropping
-    Xcode debugger stalling when devices disconnected
-    Hardware flakiness (USB / Wi-Fi) affecting MPC testing
-    Actor-isolated properties not accessible where expected
-    Perfectly “correct” Xcode error messages that were completely unhelpful
    
The final conclusion:

Trying to “convert” an older MPC project to Swift 6 is a trap.
A clean-slate rebuild is faster, clearer, and safer.

This repo is the result of that rebuild.

Swift & Xcode Versions
-    Swift 6 (strict concurrency enabled)
-    Xcode 16.2+ (tested)
-    iOS 15+

Earlier Swift versions may compile but are not supported.

### How to Run
    1.    Clone the repo
    2.    Open the .xcodeproj
    3.    Set a valid development team
    4.    Run on two physical iOS devices
    5.    Ensure:
        i.        Wi-Fi is enabled
        ii.        Bluetooth is enabled
        iii.    Devices are unlocked


### Known Limitations
-    Large file streaming is not implemented (for this app, reliability was preferred over complexity)
-    Debugging MPC with two devices is fragile
-      Simulator support is intentionally not provided

### Lessons Learned (Key Takeaways)
-    MPC delegates must not live inside actors
-    Delegate bridges are unavoidable in Swift 6
-    UI must never touch actor-isolated properties directly
-    browser.invitePeer(...) is correct — but only if:
-    advertiser is running
-    delegates are wired correctly
-    service types match exactly
-    Swift 6 improves correctness, not developer ergonomics
-    Xcode’s debugger can severely distort perceived app behavior

### Who This Is For

This repo is for developers who:
-    are using Swift 6
-    need MultipeerConnectivity
-    want a working reference
-    are tired of half-broken tutorials

It is intentionally minimal, explicit, and boring — because MPC reliability matters more than elegance.

## License

