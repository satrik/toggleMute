<p align="center">
   <img src="toggleMute_icon.png" width="180"/>
</p>   
<h1 align="center">
   toggleMute
</h1>
<p align="center"> 
   <span>macOS Touch Bar and Menu Bar App to mute/unmute the default microphone</span>
   <br><br>
   <img alt="GitHub Release" src="https://img.shields.io/github/v/release/satrik/toggleMute?style=flat&color=brightgreen">
   <img src="https://img.shields.io/badge/license-MIT-blue?style=flat" alt="License">
   <img alt="GitHub top language" src="https://img.shields.io/github/languages/top/satrik/togglemute?logo=swift&color=red">
   <img alt="GitHub Repo stars" src="https://img.shields.io/github/stars/satrik/toggleMute?style=flat&logo=Github">
</p>

> [!Important]  
> This app only mutes or unmutes the currently selected **default audio input device** on your Mac.  
> If you use an external device, you must set it as the default input device in **System Settings → Sound** for this app to work.

## Functions
- A single tap or click on the Touch Bar or Menu Bar icon toggles between mute and unmute.  
- Right-clicking the Menu Bar icon opens settings for the default unmute volume.  
   - This volume will *always* be applied when unmuting.  
   - If you change the input volume via System Settings, the app will overwrite it.  
   - Clicking the gear icon opens additional options for a global *keyboard shortcut*, *autostart*, and a *quit* button.

## Installation

### Homebrew

```shell
brew tap satrik/togglemute
brew install togglemute
xattr -rd com.apple.quarantine /Applications/toggleMute.app
```

## Manual Installation

- Download the toggleMute.dmg file from the latest release.
   - Alternatively, you can clone or download the repository.
- Mount toggleMute.dmg and move toggleMute.app to your Applications folder.
- Run (double-click) toggleMuteDisableQuarantine.command.
   - If this doesn’t work, execute xattr -rd /Applications/toggleMute.app in the Terminal.
- Launch the app for the first time via Right-click → Open and select Trust me 😉
- The Touch Bar button is only visible in the regular “Control Strip” (not the extended version) and cannot be moved elsewhere.
   - To enable it, choose Quick Actions and activate Show Control Strip.

## Update
### Homebrew

```shell
brew update
brew updgrade
xattr -rd com.apple.quarantine /Applications/toggleMute.app
```

### Manually 
Repeat the steps from the manually install section and replace the old app

## Preview:

![app_prev](img/app_prev.png)

Touch Bar Preview:

![touchbar_prev](img/touchbar_prev.png)

Menubar Preview:

![menubar_prev](img/menubar_prev.png)
