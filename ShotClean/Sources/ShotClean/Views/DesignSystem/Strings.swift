import Foundation

/// Every user-facing string, in Vietnamese. Kept in one place so it can be moved to
/// `Localizable.xcstrings` later (UI-SPEC §6). Functions build strings that contain numbers;
/// callers pass values that are already formatted with `Format`.
enum Strings {
  static let appName = "ShotClean"
  static let cancel = "Huỷ"
  static let close = "Đóng"
  static let done = "Xong"
  static let delete = "Xoá"
  static let keep = "Giữ"
  static let undo = "Hoàn tác"
  static let openSettings = "Mở Cài đặt"
  static let privacyBadge = "Xử lý trên máy · Không tải ảnh lên"

  enum Onboarding {
    static let title = "Dọn ảnh chụp màn hình, không xoá nhầm."
    static let benefitScreenshotsOnly = "Quét ảnh chụp màn hình và ảnh hỏng"
    static let benefitOnDevice = "Xử lý 100% trên máy"
    static let benefitReceipts = "Biên lai luôn được giữ lại"
    static let start = "Bắt đầu"
  }

  enum Permission {
    static let title = "Cho phép truy cập Ảnh"
    static let message =
      "ShotClean cần quyền truy cập toàn bộ thư viện để quét mọi ảnh chụp màn hình "
      + "và chỉ xoá những ảnh bạn đã chọn."
    static let pointReadOnly = "Chỉ đọc ảnh để phân tích, không sửa ảnh nào"
    static let pointNoUpload = "Không ảnh hay văn bản nào rời khỏi máy"
    static let pointConfirm = "Chỉ xoá sau khi iOS hỏi bạn xác nhận"
    static let limitedHint =
      "Nếu chỉ cho phép một số ảnh, ShotClean chỉ quét được những ảnh đó."
    static let allow = "Cho phép truy cập"
    static let deniedTitle = "Chưa có quyền truy cập Ảnh"
    static let deniedMessage =
      "Mở Cài đặt › ShotClean › Ảnh và chọn \"Toàn bộ ảnh\" để bắt đầu quét."
    static let addMore = "Chọn thêm"
    static func limitedBanner(_ count: String) -> String {
      "Chỉ đang quét \(count) ảnh bạn đã chọn"
    }
  }

  enum Scan {
    static let title = "Đang quét ảnh"
    static let finding = "Đang tìm ảnh…"
    static let checkingNew = "Đang kiểm tra ảnh mới…"
    static func progress(_ done: String, _ total: String) -> String { "\(done) / \(total)" }
    static func newPhotos(_ done: String, _ total: String) -> String {
      "Đang quét ảnh mới \(done) / \(total)"
    }
    static let accessibilityLabel = "Tiến trình quét"
  }

  enum Overview {
    static func reclaimable(_ bytes: String) -> String { "Có thể giải phóng ~\(bytes)" }
    static let nothingToClean = "Thư viện đã gọn gàng"
    static func fromPhotos(_ candidates: String, _ total: String) -> String {
      "từ \(candidates) ảnh / \(total) ảnh đã quét"
    }
    static let needsReview = "Cần bạn xem"
    static let protectedSection = "Được bảo vệ"
    static func protectedDetail(_ count: String) -> String { "\(count) ảnh · luôn giữ lại" }
    static func quickClean(_ count: String) -> String { "Dọn nhanh \(count) ảnh" }
    static let swipeReview = "Vuốt duyệt"
    static func cleanNow(_ count: String, _ bytes: String) -> String {
      "Dọn ngay \(count) ảnh · \(bytes)"
    }
    static func cleanNowCount(_ count: String) -> String { "Dọn ngay \(count) ảnh" }
    static let cleanNowHint = "Mở bản tóm tắt để xác nhận trước khi xoá"
    static func selectCategory(_ category: String) -> String { "Chọn cả nhóm \(category)" }
    static func deselectCategory(_ category: String) -> String { "Bỏ chọn nhóm \(category)" }
    static let settings = "Cài đặt"
    static let emptyTitle = "Chưa có ảnh chụp màn hình"
    static let emptyMessage = "Khi bạn chụp màn hình, ShotClean sẽ giúp bạn dọn chúng ở đây."
    static func unavailable(_ count: String) -> String {
      "\(count) ảnh chỉ có trên iCloud nên chưa phân tích được"
    }
    static func photoCount(_ count: String) -> String { "\(count) ảnh" }
    static func chartLabel(_ parts: String) -> String { "Dung lượng theo nhóm: \(parts)" }
  }

  enum Grid {
    static let selectAll = "Chọn tất cả"
    static let selectNone = "Bỏ chọn"
    static let sort = "Sắp xếp"
    static let sortOldest = "Cũ nhất"
    static let sortLargest = "Lớn nhất"
    static let selected = "Đã chọn để xoá"
    static let notSelected = "Chưa chọn"
    static let showDetail = "Xem chi tiết"
    static let dragHint = "Chạm ảnh để chọn. Kéo ngang qua các ảnh để chọn nhanh nhiều ảnh."
    static func deleteButton(_ count: String, _ bytes: String) -> String {
      "Xoá \(count) ảnh · \(bytes)"
    }
    static let empty = "Không còn ảnh nào trong nhóm này"
    static let receiptNote =
      "Biên lai không bao giờ được chọn sẵn. Bạn vẫn có thể tự chọn nếu chắc chắn muốn xoá."
  }

  enum Detail {
    static let title = "Chi tiết ảnh"
    static let reason = "Lý do"
    static let captured = "Ngày chụp"
    static let size = "Dung lượng"
    static let pixels = "Kích thước"
    static let unknown = "Chưa rõ"
    static let ocrText = "Văn bản nhận dạng (POC)"
    static let noText = "Không nhận ra chữ nào"
    static let select = "Chọn để xoá"
    static let deselect = "Bỏ chọn"
  }

  enum Cluster {
    static let exactTitle = "Giống hệt"
    static let nearTitle = "Gần giống"
    static let exactIntro =
      "Mỗi cụm gợi ý giữ 1 ảnh, các ảnh còn lại đã được chọn sẵn. Chạm ảnh để chọn hoặc bỏ "
      + "chọn, nhấn giữ ảnh để đặt làm ảnh giữ lại."
    static let nearIntro =
      "Các ảnh gần giống nhau. Chạm ảnh để chọn hoặc bỏ chọn, nhấn giữ để đổi ảnh giữ lại."
    static let selectAll = "Xoá cả nhóm"
    static let selectNone = "Bỏ chọn nhóm"
    static let selectAllClusters = "Chọn ảnh thừa ở mọi nhóm"
    static let keeperTag = "Giữ"
    static let keeperOldest = "Cũ nhất"
    /// Core keeper rule for near duplicates: largest pixel area, ties → oldest (REV-19).
    static let keeperLargest = "Lớn nhất"
    static let keeperChosen = "Bạn chọn"
    static let keeperNewest = "Mới nhất"
    static let keeperProtected = "Được bảo vệ"
    static let burstTitle = "Chụp liên tiếp"
    static let burstIntro =
      "Ảnh chụp màn hình chụp liên tiếp trong vài giây. Ảnh sau cùng được giữ, các ảnh trước "
      + "đã được chọn sẵn. Chạm ảnh để chọn hoặc bỏ chọn, nhấn giữ để giữ ảnh đó thay thế."
    static let compare = "So sánh"
    static let selectOthers = "Chọn các ảnh còn lại"
    static let keepBest = "Giữ 1 ảnh tốt nhất"
    static let keepBestEverywhere = "Giữ ảnh tốt nhất ở mọi nhóm"
    static let setKeeper = "Đặt làm ảnh giữ lại"
    static let isKeeper = "Ảnh giữ lại"
    static let receipt = "Biên lai"
    static func header(_ kind: String, _ count: String) -> String { "\(kind) · \(count) ảnh" }
    static func member(_ index: Int, _ total: Int, _ date: String) -> String {
      "Ảnh \(index) trên \(total), chụp \(date)"
    }
    static let compareTitle = "So sánh"
    static let compareWith = "So với"
    static func photoNumber(_ index: Int) -> String { "Ảnh \(index)" }
    static let empty = "Không có cụm nào"
  }

  enum Swipe {
    static let title = "Vuốt duyệt"
    static func queue(_ count: String, _ bytes: String) -> String {
      "Hàng chờ: \(count) ảnh · \(bytes)"
    }
    static func position(_ current: Int, _ total: Int) -> String { "\(current) / \(total)" }
    static let finishedTitle = "Đã duyệt hết"
    static func finishedMessage(_ count: String) -> String {
      "Có \(count) ảnh trong hàng chờ xoá. Bấm \"Xong\" để xem lại trước khi xoá."
    }
    static let emptyTitle = "Không có ảnh để duyệt"
    static let emptyMessage = "Chưa có ảnh nào được đề xuất xoá."
    static let hint = "Vuốt trái để cho vào hàng chờ xoá, vuốt phải để giữ."
    static func captured(_ date: String) -> String { "Chụp \(date)" }
  }

  enum Deletion {
    static func title(_ count: String) -> String { "Xoá \(count) ảnh" }
    static func size(_ bytes: String) -> String { "~\(bytes)" }
    static let recentlyDeletedNote =
      "Ảnh sẽ nằm trong \"Đã xoá gần đây\" 30 ngày. iOS sẽ hỏi bạn xác nhận thêm một lần."
    static let confirm = "Xoá"
    static let cancelled = "Bạn đã huỷ trên hộp thoại của iOS. Chưa xoá ảnh nào."
    static let nothingToDelete = "Các ảnh này không còn trong thư viện. Không có gì để xoá."
    static func failed(_ message: String) -> String { "Không xoá được: \(message)" }
    static let resultTitle = "Đã dọn xong"
    static func resultCount(_ count: String) -> String { "Đã chuyển \(count) ảnh vào thùng rác" }
    static let honestNote =
      "Dung lượng được trả lại hoàn toàn sau khi bạn dọn \"Đã xoá gần đây\"."
    static let howTo = "Mở Ảnh › Bộ sưu tập › Đã xoá gần đây › Chọn › Xoá tất cả."
    static let backToOverview = "Về Tổng quan"
  }

  enum Settings {
    static let title = "Cài đặt"
    static let rules = "Quy tắc"
    static let qrAge = "Mã QR cũ hơn"
    static let ticketGrace = "Ân hạn vé"
    static let orderAge = "Đơn hàng cũ hơn"
    static let nearSensitivity = "Độ nhạy gần trùng"
    static let nearGap = "Chụp cách nhau tối đa"
    static let duplicateKeeper = "Khi trùng, giữ ảnh"
    static let keeperOldest = "Cũ nhất"
    static let rulesFooter =
      "Thay đổi được áp dụng ngay cho kết quả đã quét, không cần quét lại. "
      + "Lựa chọn bạn đã tự đánh dấu được giữ nguyên."
    static let filters = "Bộ lọc tự chọn sẵn"
    static let filtersFooter =
      "Chỉ những loại được bật mới được chọn sẵn để xoá và đưa vào hàng chờ vuốt. "
      + "Biên lai chuyển khoản không bao giờ được chọn sẵn. Ảnh gần trùng và ảnh tài liệu "
      + "chỉ được đưa vào hàng chờ duyệt."
    static let duplicates = "Ảnh trùng"
    static let preselectNear = "Chọn sẵn ảnh gần giống"
    static let keeperNewest = "Mới nhất"
    static let keeperAutomatic = "Tự động (cũ nhất / nét nhất)"
    static let keeperLargestFile = "Dung lượng lớn nhất"
    static let resetDefaults = "Khôi phục mặc định"
    static func sensitivity(_ value: String) -> String { "Độ nhạy: \(value)" }
    static let sensitivityLow = "Chặt"
    static let sensitivityHigh = "Rộng"
    static let protection = "Bảo vệ"
    static let alwaysKeepReceipts = "Luôn giữ biên lai"
    static let privacy = "Quyền riêng tư"
    static let privacyText =
      "Mọi phân tích (nhận dạng chữ, mã QR, so sánh ảnh) chạy trên iPhone của bạn. "
      + "ShotClean không có kết nối mạng và không gửi ảnh hay văn bản ra ngoài."
    static let photoAccess = "Quyền truy cập Ảnh"
    static let other = "Khác"
    static let rescanAll = "Quét lại toàn bộ"
    static let scanning = "Đang quét…"
    static let version = "Phiên bản"
    static let debug = "Gỡ lỗi"
    static func days(_ count: Int) -> String { "\(count) ngày" }
    static func minutes(_ count: Int) -> String { "\(count) phút" }
    static func seconds(_ count: Int) -> String { "\(count) giây" }
    static let oldScreenshotAge = "Ảnh chụp màn hình cũ hơn"
    static let burstGap = "Chụp liên tiếp cách nhau"
    static let scope = "Phạm vi quét"
    static let scanCameraPhotos = "Quét cả ảnh chụp bằng camera"
    static let scopeFooter =
      "Tìm ảnh tối đen, cháy sáng, bị mờ và ảnh trùng trong ảnh thường. Bật hoặc tắt sẽ "
      + "quét lại phần thay đổi."
    static let alwaysKeepProtected = "Luôn giữ ảnh yêu thích, trong album, đã chỉnh sửa"
    static let shortcuts = "Phím tắt"
    static let shortcutURL = "shotclean://clean"
    static let shortcutsText =
      "Muốn dọn bằng một chạm? Mở ứng dụng Phím tắt, tạo phím tắt hoặc mục Tự động hoá cá nhân "
      + "với tác vụ \"Mở URL\" và nhập shotclean://clean. Khi chạy, ShotClean quét ảnh mới rồi "
      + "mở màn hình xác nhận với các ảnh đã chọn sẵn — bạn chỉ cần xác nhận."
    static let shortcutsNote =
      "ShotClean không bao giờ tự chạy hay tự xoá ảnh trong nền. Mọi lần xoá đều cần bạn "
      + "xác nhận trên hộp thoại của iOS."
    static let copyURL = "Sao chép URL"
    static let copied = "Đã sao chép"
    static func distance(_ value: String) -> String { "Vừa (khoảng cách < \(value))" }
    static let preset = "Mức dọn"
    static let presetCautious = "Thận trọng"
    static let presetBalanced = "Cân bằng"
    static let presetAggressive = "Mạnh tay"
    static let presetCustom = "Tuỳ chỉnh"
    static let presetCautiousFooter =
      "Chỉ chọn sẵn ảnh chắc chắn thừa. Ảnh gần giống và ảnh hỏng để bạn tự duyệt, ảnh chụp "
      + "màn hình cũ sau 180 ngày."
    static let presetBalancedFooter =
      "Mặc định. Chọn sẵn ảnh trùng, chụp liên tiếp, ảnh hỏng và ảnh chụp màn hình cũ sau 90 ngày."
    static let presetAggressiveFooter =
      "Chọn sẵn cả ảnh gần giống và ảnh chụp màn hình cũ sau 30 ngày. Bạn vẫn xem lại trước khi xoá."
    static let presetCustomFooter =
      "Bạn đã chỉnh riêng. Chọn một mức ở trên để quay về bộ quy tắc có sẵn."
    static func preselectPreview(_ count: String, _ bytes: String) -> String {
      "Sẽ chọn sẵn \(count) ảnh · \(bytes)"
    }
    static func preselectPreviewCount(_ count: String) -> String { "Sẽ chọn sẵn \(count) ảnh" }
    static let advanced = "Nâng cao"
    static let sensitivityMedium = "Vừa"
    static func sensitivityCustom(_ value: String) -> String { "Khác (\(value))" }
  }

  enum Debug {
    static let title = "Gỡ lỗi"
    static let counts = "Số liệu"
    static let screenshots = "Ảnh đã quét"
    static let analyzed = "Đã phân tích"
    static let unavailable = "Chỉ có trên iCloud"
    static let clusters = "Cụm trùng / gần trùng"
    static let preselected = "Chọn sẵn để xoá"
    static let selected = "Đang chọn"
    static let swipeQueue = "Hàng chờ vuốt"
    static let ocrLanguages = "Ngôn ngữ OCR"
    static let ocrMaxDimension = "Cạnh dài ảnh OCR"
    static func pixels(_ value: String) -> String { "\(value) px" }
    static let loading = "Đang đọc…"
    static let suggestion = "Đề xuất"
    static let reason = "Lý do"
    static let ocr = "Văn bản OCR"
    static let search = "Tìm theo lý do, chữ hoặc id"
  }

  enum Suggestion {
    static let delete = "Xoá"
    static let keep = "Giữ"
    static let review = "Cần xem"
    static let none = "Không"
  }

  enum Category {
    static let exact = "Trùng hoàn toàn"
    static let near = "Gần trùng"
    static let qr = "QR không cần thiết"
    static let ticket = "Vé hết hạn"
    static let order = "Đơn hàng hết hạn"
    static let receipt = "Biên lai chuyển khoản"
    static let burst = "Chụp liên tiếp"
    static let oldScreenshot = "Ảnh chụp màn hình cũ"
    static let lowQuality = "Ảnh hỏng / mờ / tối"
    static let utility = "Ảnh tài liệu / tiện ích"
    static let other = "Khác"

    static let exactShort = "Trùng"
    static let nearShort = "Gần trùng"
    static let qrShort = "QR"
    static let ticketShort = "Vé"
    static let orderShort = "Đơn"
    static let receiptShort = "Biên lai"
    static let burstShort = "Liên tiếp"
    static let oldScreenshotShort = "Cũ"
    static let lowQualityShort = "Ảnh hỏng"
    static let utilityShort = "Tài liệu"
    static let otherShort = "Khác"

    static let exactSummary = "Giữ 1 ảnh mỗi cụm, xoá bản trùng"
    static let nearSummary = "Ảnh gần giống, bạn chọn ảnh giữ"
    static let qrSummary = "Ảnh chủ yếu là mã QR, đã cũ"
    static let ticketSummary = "Vé có ngày đã qua"
    static let orderSummary = "Đơn hàng đã quá hạn theo dõi"
    static let receiptSummary = "Luôn giữ lại"
    static let burstSummary = "Giữ ảnh chụp sau cùng, xoá các ảnh trước"
    static let oldScreenshotSummary = "Ảnh chụp màn hình đã cũ, không còn cần"
    static let lowQualitySummary = "Ảnh tối đen, cháy sáng hoặc bị mờ"
    static let utilitySummary = "Ảnh giấy tờ, hoá đơn… đã cũ, bạn xem lại"
    static let otherSummary = ""
  }

  enum Background {
    static let title = "Đang quét ảnh"
    static func progress(_ done: String, _ total: String) -> String { "\(done) / \(total) ảnh" }
    static let doneTitle = "Đã quét xong"
    static func doneBody(_ count: String, _ bytes: String) -> String {
      "\(count) ảnh có thể dọn · \(bytes). Mở ShotClean để xem và xoá."
    }
    static let doneNothing = "Không có ảnh nào cần dọn."
  }
}
