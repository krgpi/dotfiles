-- Captive Portal Monitor for Starbucks WiFi (at_STARBUCKS_Wi2)
-- 設定でSSIDを追加可能。認証切れを検知して自動再認証を行う。

local M = {}

-- ============================================================
-- 設定
-- ============================================================
M.config = {
    -- 監視対象のSSID（Captive Portalがあるネットワーク）
    targetSSIDs = {
        "at_STARBUCKS_Wi2",
        -- 必要に応じて追加: "OTHER_CAPTIVE_SSID",
    },

    -- チェック間隔（秒）
    checkInterval = 30,

    -- 認証切れ検知後の再チェック間隔（秒）- 連続失敗時の負荷軽減
    retryInterval = 10,

    -- 連続失敗時の最大リトライ回数（超えたら通常間隔に戻る）
    maxRetries = 3,

    -- Captive Portal検知用URL（macOSと同じ）
    detectURL = "http://captive.apple.com/hotspot-detect.html",

    -- 正常時のレスポンスに含まれる文字列
    expectedResponse = "Success",

    -- 自動認証を有効にするか
    autoAuthenticate = true,

    -- 通知を表示するか
    showNotifications = true,

    -- デバッグログを有効にするか
    debug = true,
}

-- ============================================================
-- 内部状態
-- ============================================================
local checkTimer = nil
local retryCount = 0
local isMonitoring = false
local lastSSID = nil
local wifiWatcher = nil

-- ============================================================
-- ユーティリティ
-- ============================================================
local function log(message)
    if M.config.debug then
        print("[CaptivePortal] " .. os.date("%H:%M:%S") .. " " .. message)
    end
end

local function notify(title, message, withdraw)
    if M.config.showNotifications then
        local n = hs.notify.new({
            title = title,
            informativeText = message,
            withdrawAfter = withdraw or 5,
        })
        n:send()
        return n
    end
end

local function getCurrentSSID()
    local output, status = hs.execute("networksetup -getairportnetwork en0 2>/dev/null")
    if status and output then
        local ssid = output:match("Current Wi%-Fi Network: (.+)")
        if ssid then
            return ssid:gsub("^%s*(.-)%s*$", "%1") -- trim
        end
    end
    return nil
end

local function isTargetSSID(ssid)
    if not ssid then return false end
    for _, target in ipairs(M.config.targetSSIDs) do
        if ssid == target then
            return true
        end
    end
    return false
end

-- ============================================================
-- Captive Portal検知
-- ============================================================
local function checkCaptivePortal(callback)
    log("Checking captive portal status...")

    hs.http.asyncGet(M.config.detectURL, nil, function(status, body, headers)
        if status == 200 and body and body:find(M.config.expectedResponse) then
            log("Connection OK - Internet is accessible")
            callback(true, nil)
        elseif status == 200 then
            -- 200だがSuccessではない = Captive Portalにリダイレクトされている
            log("Captive portal detected (status=200, but not Success)")
            callback(false, "captive_portal")
        elseif status == 302 or status == 301 then
            log("Captive portal detected (redirect)")
            callback(false, "captive_portal")
        elseif status == 0 or status == -1 then
            log("Network error - no connectivity")
            callback(false, "no_network")
        else
            log("Unexpected status: " .. tostring(status))
            callback(false, "unknown")
        end
    end)
end

-- ============================================================
-- スタバWiFi自動認証
-- ============================================================
local function authenticateStarbucks()
    log("Attempting automatic authentication for Starbucks WiFi...")

    -- 認証ページのURLリスト（順番に試す）
    local authURLs = {
        "https://service.wi2.ne.jp/wi2auth/at_STARBUCKS_Wi2/index.html",
        "http://service.wi2.ne.jp/wi2net/AutoLogin/2/",
    }

    -- JavaScriptで自動クリックを実行するAppleScript
    local jsAutoClick = [[
        (function() {
            // 「インターネットに接続」ボタン
            var nextBtn = document.getElementById('button_next_page');
            if (nextBtn) { nextBtn.click(); return 'clicked_next'; }

            // 「同意する」ボタン
            var acceptBtn = document.getElementById('button_accept');
            if (acceptBtn) { acceptBtn.click(); return 'clicked_accept'; }

            // 別の形式のボタンを探す
            var buttons = document.querySelectorAll('input[type="submit"], button[type="submit"], .btn, .button');
            for (var i = 0; i < buttons.length; i++) {
                var btn = buttons[i];
                var text = (btn.value || btn.textContent || '').toLowerCase();
                if (text.indexOf('接続') >= 0 || text.indexOf('同意') >= 0 ||
                    text.indexOf('続') >= 0 || text.indexOf('connect') >= 0 ||
                    text.indexOf('agree') >= 0 || text.indexOf('accept') >= 0) {
                    btn.click();
                    return 'clicked_generic: ' + text;
                }
            }

            return 'no_button_found';
        })()
    ]]

    -- Captive Portal ウィンドウを開いて自動認証
    local applescript = string.format([[
        tell application "System Events"
            -- Captive Network Assistantが開いていれば使う
            set captiveApp to null
            try
                set captiveApp to application process "Captive Network Assistant"
            end try

            if captiveApp is not null then
                tell captiveApp
                    set frontmost to true
                end tell
                delay 1
                -- WebViewでJavaScriptを実行（Captive Network Assistantでは難しい）
            end if
        end tell

        -- Safariで認証ページを開く
        tell application "Safari"
            activate
            open location "%s"
            delay 2

            -- JavaScriptを実行
            set jsResult to do JavaScript "%s" in document 1

            delay 1

            -- 2回目のクリック（同意ページ用）
            set jsResult2 to do JavaScript "%s" in document 1

            return jsResult & " -> " & jsResult2
        end tell
    ]], authURLs[1], jsAutoClick:gsub('"', '\\"'):gsub('\n', ' '), jsAutoClick:gsub('"', '\\"'):gsub('\n', ' '))

    local ok, result = hs.osascript.applescript(applescript)
    if ok then
        log("Authentication script executed: " .. tostring(result))
        notify("WiFi認証", "自動認証を実行しました", 3)

        -- 認証後に再チェック
        hs.timer.doAfter(3, function()
            checkCaptivePortal(function(connected, reason)
                if connected then
                    notify("WiFi認証", "インターネット接続が復旧しました ✓", 5)
                    retryCount = 0
                else
                    log("Still not connected after authentication attempt")
                    notify("WiFi認証", "認証が完了していない可能性があります。手動で確認してください。", 10)
                end
            end)
        end)
    else
        log("Authentication script failed: " .. tostring(result))
        notify("WiFi認証エラー", "自動認証に失敗しました", 5)
    end
end

-- ============================================================
-- シンプルな再認証ウィンドウ表示
-- ============================================================
local function openCaptivePortalWindow()
    log("Opening captive portal window...")

    -- macOSのCaptive Network Assistantを起動
    hs.execute("open -a 'Captive Network Assistant' 2>/dev/null || open 'http://captive.apple.com'")

    notify("WiFi再認証が必要", "認証ウィンドウを開きました", 5)
end

-- ============================================================
-- 定期チェック
-- ============================================================
local function performCheck()
    local ssid = getCurrentSSID()

    if not isTargetSSID(ssid) then
        log("Not on target SSID (current: " .. tostring(ssid) .. "), skipping check")
        retryCount = 0
        return
    end

    log("On target SSID: " .. ssid)

    checkCaptivePortal(function(connected, reason)
        if connected then
            retryCount = 0
            -- 接続OK、何もしない
        else
            retryCount = retryCount + 1
            log("Connection lost! Retry count: " .. retryCount)

            if reason == "captive_portal" then
                notify("WiFi認証切れ", "再認証が必要です (" .. ssid .. ")", 10)

                if M.config.autoAuthenticate and ssid == "at_STARBUCKS_Wi2" then
                    -- スタバWiFiは自動認証を試みる
                    authenticateStarbucks()
                else
                    -- その他は手動認証ウィンドウを開く
                    openCaptivePortalWindow()
                end
            elseif reason == "no_network" then
                notify("ネットワークエラー", "インターネットに接続できません", 5)
            end

            -- リトライ間隔を調整
            if retryCount < M.config.maxRetries then
                if checkTimer then
                    checkTimer:setNextTrigger(M.config.retryInterval)
                end
            end
        end
    end)
end

-- ============================================================
-- WiFi変更監視
-- ============================================================
local function onWifiChange()
    local ssid = getCurrentSSID()

    if ssid ~= lastSSID then
        log("WiFi changed: " .. tostring(lastSSID) .. " -> " .. tostring(ssid))
        lastSSID = ssid
        retryCount = 0

        if isTargetSSID(ssid) then
            notify("Captive Portal監視", ssid .. " に接続しました。監視を開始します。", 3)
            -- 接続直後は少し待ってからチェック
            hs.timer.doAfter(3, performCheck)
        end
    end
end

-- ============================================================
-- 公開API
-- ============================================================

-- 監視を開始
function M.start()
    if isMonitoring then
        log("Already monitoring")
        return
    end

    log("Starting captive portal monitor...")
    isMonitoring = true
    lastSSID = getCurrentSSID()

    -- WiFi変更を監視
    wifiWatcher = hs.wifi.watcher.new(onWifiChange)
    wifiWatcher:start()

    -- 定期チェックタイマー
    checkTimer = hs.timer.doEvery(M.config.checkInterval, performCheck)

    -- 初回チェック
    if isTargetSSID(lastSSID) then
        hs.timer.doAfter(1, performCheck)
    end

    notify("Captive Portal Monitor", "監視を開始しました", 3)
    log("Monitor started. Current SSID: " .. tostring(lastSSID))
end

-- 監視を停止
function M.stop()
    if not isMonitoring then
        log("Not monitoring")
        return
    end

    log("Stopping captive portal monitor...")
    isMonitoring = false

    if checkTimer then
        checkTimer:stop()
        checkTimer = nil
    end

    if wifiWatcher then
        wifiWatcher:stop()
        wifiWatcher = nil
    end

    notify("Captive Portal Monitor", "監視を停止しました", 3)
end

-- 手動でチェックを実行
function M.checkNow()
    log("Manual check triggered")
    performCheck()
end

-- 設定を更新
function M.configure(opts)
    for k, v in pairs(opts) do
        M.config[k] = v
    end
    log("Configuration updated")
end

-- ステータスを取得
function M.status()
    return {
        isMonitoring = isMonitoring,
        currentSSID = getCurrentSSID(),
        isTargetSSID = isTargetSSID(getCurrentSSID()),
        retryCount = retryCount,
    }
end

return M
