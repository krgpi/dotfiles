#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macos.sh is macOS only"
    exit 1
fi

echo "Applying macOS defaults"

# Dock
defaults write com.apple.dock orientation -string left
defaults write com.apple.dock tilesize -int 44
defaults write com.apple.dock magnification -bool false
defaults write com.apple.dock autohide -bool false
defaults write com.apple.dock show-recents -bool false
defaults write com.apple.dock minimize-to-application -bool false
defaults write com.apple.dock mineffect -string genie
defaults write com.apple.dock show-process-indicators -bool true
defaults write com.apple.dock expose-group-apps -bool true
defaults write com.apple.dock showAppExposeGestureEnabled -bool false
defaults write com.apple.dock showMissionControlGestureEnabled -bool true
defaults write com.apple.dock workspaces-edge-delay -int 2

# ホットコーナー（1=無効, 3=アプリケーションウィンドウ）
defaults write com.apple.dock wvous-tl-corner -int 1
defaults write com.apple.dock wvous-tr-corner -int 1
defaults write com.apple.dock wvous-bl-corner -int 3
defaults write com.apple.dock wvous-br-corner -int 1
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-modifier -int 0

# 外観・キーボード・入力
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool true
defaults write NSGlobalDomain AppleReduceDesktopTinting -bool true
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool true
defaults write NSGlobalDomain AppleActionOnDoubleClick -string Maximize
defaults write NSGlobalDomain AppleMiniaturizeOnDoubleClick -bool false
defaults write NSGlobalDomain AppleWindowTabbingMode -string always
defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool true
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 1
# 長押しのアクセント入力を切ってキーリピートを優先する
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
# Tab ですべてのコントロールを移動できるようにする
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
defaults write NSGlobalDomain "com.apple.keyboard.fnState" -bool false
defaults write NSGlobalDomain NSAllowContinuousSpellChecking -bool false

# ウィンドウのアニメーションを止める
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# ポインタ・スクロール
defaults write NSGlobalDomain "com.apple.mouse.scaling" -float 3
defaults write NSGlobalDomain "com.apple.trackpad.scaling" -float 3
defaults write NSGlobalDomain "com.apple.swipescrolldirection" -bool true
# 2本指スワイプの「戻る/進む」を無効にする
defaults write NSGlobalDomain AppleEnableSwipeNavigateWithScrolls -bool false
defaults write NSGlobalDomain AppleEnableMouseSwipeNavigateWithScrolls -bool false

# トラックパッド（内蔵と Bluetooth の両方に同じ設定を書く）
for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    defaults write "$domain" Clicking -bool true
    defaults write "$domain" Dragging -bool false
    defaults write "$domain" DragLock -bool false
    defaults write "$domain" TrackpadRightClick -bool true
    defaults write "$domain" TrackpadCornerSecondaryClick -int 0
    defaults write "$domain" TrackpadThreeFingerDrag -bool false
    defaults write "$domain" TrackpadThreeFingerTapGesture -int 0
    defaults write "$domain" TrackpadThreeFingerHorizSwipeGesture -int 2
    defaults write "$domain" TrackpadThreeFingerVertSwipeGesture -int 2
    defaults write "$domain" TrackpadFourFingerHorizSwipeGesture -int 2
    defaults write "$domain" TrackpadFourFingerVertSwipeGesture -int 2
    defaults write "$domain" TrackpadTwoFingerDoubleTapGesture -int 1
    # 右端から2本指スワイプで通知センター
    defaults write "$domain" TrackpadTwoFingerFromRightEdgeSwipeGesture -int 3
    defaults write "$domain" TrackpadHandResting -bool true
    defaults write "$domain" TrackpadMomentumScroll -bool true
done

# Finder
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool false
defaults write com.apple.finder ShowSidebar -bool true
defaults write com.apple.finder ShowPreviewPane -bool false
defaults write com.apple.finder ShowRecentTags -bool false
defaults write com.apple.finder FXPreferredViewStyle -string icnv
defaults write com.apple.finder FXPreferredGroupBy -string Kind
defaults write com.apple.finder FXArrangeGroupViewBy -string Name
# 検索は現在のフォルダを対象にする（SCcf）／新規ウィンドウは「最近の項目」（PfAF）
defaults write com.apple.finder FXDefaultSearchScope -string SCcf
defaults write com.apple.finder NewWindowTarget -string PfAF
# 30日経ったゴミ箱の項目を自動で消す
defaults write com.apple.finder FXRemoveOldTrashItems -bool true
defaults write com.apple.finder FinderSpawnTab -bool true
defaults write com.apple.finder _FXSortFoldersFirst -bool true
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# デスクトップに出すアイコン
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool false

# ネットワーク/USB ボリュームに .DS_Store を作らない
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# スクリーンショット
defaults write com.apple.screencapture location -string "~/Downloads"
defaults write com.apple.screencapture style -string window
defaults write com.apple.screencapture target -string file

# メニューバーの時計
defaults write com.apple.menuextra.clock ShowSeconds -bool true
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool true
defaults write com.apple.menuextra.clock ShowDate -int 0
defaults write com.apple.menuextra.clock ShowAMPM -bool true
defaults write com.apple.menuextra.clock FlashDateSeparators -bool true

# メニューバーの標準アイコン（sketchybar 側で出すぶんは隠す）
defaults write com.apple.controlcenter "NSStatusItem Visible WiFi" -bool false
defaults write com.apple.controlcenter "NSStatusItem Visible UserSwitcher" -bool false
defaults write com.apple.controlcenter "NSStatusItem Visible Shortcuts" -bool false
defaults write com.apple.controlcenter "NSStatusItem Visible FaceTime" -bool false
defaults write com.apple.controlcenter "NSStatusItem Visible BentoBox" -bool true

for app in Dock Finder SystemUIServer ControlCenter; do
    killall "$app" >/dev/null 2>&1 || true
done

echo "Done. 一部の設定は再ログイン後に反映される"
