## toggleMute

> This App only mutes/unmutes the default selected audio input device of your Mac. If you use an external device you have to set it as the default audio device in the macOS system settings to make it work with this App.

> [!NOTE]
> I don't use a MacBook with Touch Bar anymore. So if there are any issues with the Touch Bar, then I won't notice it. Please open an issue if there are any problems.

### functions
- Single tab/click on the Touch Bar or the Menubar icon will toggle between mute and unmute
- Right click on the Menubar icon will show the setting for the default unmute volume. 
   - this volume will _always_ be set if you unmute
   - if you change the input volume via the system settings, the app will overwrite it
   - click on the little gear symbol will show the option to set a global _Keyboard Shortcut_, the option for _Autostart_ and a _Quit_ button

### install
#### homebrew tap

```shell
brew tap satrik/togglemute
brew install --no-quarantine togglemute
```

#### manually

- download the toggleMute.dmg form the [latest](https://github.com/satrik/toggleMute/releases/latest) release
   - alternatively download or clone the repository
- mount the toggleMute.dmg and move toggleMute.app into the Applications folder
- execute (just double click) the `toggleMuteDisableQuarantine.command`
   - if this does not work, you have to execute `xattr -cr /Applications/toggleMute.app` in a terminal
- start the App the first time via right click > open and "Trust me" :wink:
- the Touch Bar button is only visible in the normal "control strip" (not the extended) and can't be moved to any other place
   - so you have to choose for example "Quick Actions" and activate "Show Control Stip"

### update
#### homebrew

```shell
brew update
brew updgrade --no-quarantine
```

#### manually 
Repeat the steps from the manually install section and replace the old app

### app preview:

![app_prev](img/app_prev.png)

Touch Bar Preview:

![touchbar_prev](img/touchbar_prev.png)

Menubar Preview:

![menubar_prev](img/menubar_prev.png)
