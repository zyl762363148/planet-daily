import AppKit
import Foundation

@main
struct StoreRefreshChecks {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("digest-refresh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("data"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        setenv("DIGEST_DATA_ROOT", folder.path, 1)
        let config: [String: Any] = ["tts": ["enabled": false], "weather": ["enabled": false], "modules": ["enabled": ["ai"]]]
        try JSONSerialization.data(withJSONObject: config).write(to: folder.appendingPathComponent("config.json"))
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.string(from: Date())
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterday = formatter.string(from: yesterdayDate)
        func publish(_ day: String, marker: String, latest: Bool) throws {
            let category: [String: Any] = ["id": "ai", "name": "人工智能", "icon": "brain", "color": "#123456", "brief": marker, "items": []]
            let digest: [String: Any] = ["date": day, "generated_at": "2026-11-06T01:00:00+08:00", "categories": [category]]
            let bytes = try JSONSerialization.data(withJSONObject: digest)
            let url = folder.appendingPathComponent("data/" + day + ".json")
            try bytes.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(marker == "第二次更新" ? 3 : 0)], ofItemAtPath: url.path)
            if latest { try bytes.write(to: folder.appendingPathComponent("data/latest.json"), options: .atomic) }
        }
        try publish(yesterday, marker: "昨日", latest: true)
        let store = DigestStore(startBackgroundServices: false)
        assert(store.dateString == yesterday)
        try publish(today, marker: "首次更新", latest: true)
        store.refreshOnActivate()
        assert(store.dateString == today, "默认页面必须从昨日跟进到今日")
        assert(store.digest?.categories.first?.brief == "首次更新")
        store.selectDate(yesterdayDate)
        try publish(today, marker: "第二次更新", latest: true)
        store.refreshOnActivate()
        assert(store.dateString == yesterday, "主动浏览历史时不跳转")
        assert(store.availableDateStrings.contains(today), "归档列表仍应知道新日期")
        let missingDay = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        store.selectDate(missingDay); store.refreshOnActivate()
        assert(store.dateString == formatter.string(from: missingDay), "历史日期无数据时也不强制跳转")
        store.goToday(); store.refreshOnActivate()
        assert(store.dateString == today)
        assert(store.digest?.categories.first?.brief == "第二次更新")
        print("通过：跨天跟随最新、同日更新、手动历史不跳转、回到今天与归档日期刷新")
    }
}
