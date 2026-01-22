-- ネットワークが切れたら通知する
status_watcher = hs.network.reachability.forHostName("google.com")

if status_watcher then
    status_watcher:setCallback(function(self, flags)
        local isReachable = (flags & hs.network.reachability.flags.reachable) ~= 0

        if isReachable then
            hs.notify.new({ title = "Network Monitor", informativeText = "オンラインに復旧しました" }):send()
        else
            hs.notify.new({ title = "Network Monitor", informativeText = "オフラインになりました" }):send()
        end
    end)

    status_watcher:start()
end
