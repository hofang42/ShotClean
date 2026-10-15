/// Realistic, anonymized OCR text samples (names, account numbers and codes are fake).
/// R3 will add file-based fixtures; these stay inline as a fast smoke set.
enum OCRSample {
  static let vietcombankTransfer = """
    Vietcombank
    Chuyển tiền thành công
    -2.500.000 VND
    14:32 Thứ Hai 12/10/2026
    Tài khoản nhận
    NGUYEN VAN A
    0123456789
    Ngân hàng TMCP Á Châu (ACB)
    Mã giao dịch 5123456789
    Nội dung NGUYEN VAN B chuyen tien
    """

  static let mbBankTransfer = """
    MB
    Giao dịch thành công!
    500,000 VND
    Tài khoản thụ hưởng
    TRAN THI B
    9704 2290 1234 5678
    Mã giao dịch FT26285123456
    08/10/2026 09:15:22
    """

  static let techcombankTransfer = """
    Techcombank
    Chuyển khoản thành công
    Số tiền
    1.200.000 đ
    Đến: LE VAN C
    Số tài khoản 19031234567890
    Ngày 05/10/2026 lúc 20:01
    """

  /// No explicit success phrase: wallet name + field + amount.
  static let momoTransfer = """
    MoMo
    Số tiền 150.000đ
    Người nhận PHAM THI D
    Mã giao dịch 12345678901
    Thời gian 10:42 - 03/10/2026
    """

  /// Flight paid successfully: receipt wins over ticket.
  static let flightPaymentReceipt = """
    Thanh toán thành công
    Chuyến bay VJ123 SGN - HAN
    Ngày bay 12/09/2026
    Tổng tiền 1.580.000 VND
    Mã đặt chỗ ABC123
    """

  static let shopeeDeliveredOrder = """
    Shopee
    Đơn hàng đã giao
    Mã đơn hàng 260815ABCDEF12
    Giao hàng nhanh
    Ngày giao 15/08/2026
    Tổng thanh toán ₫259.000
    """

  static let ghnTracking = """
    GHN Express
    Mã vận đơn: GHNABCD1234
    Đang giao hàng
    Cập nhật 20/09/2026 14:20
    """

  static let vietjetBoardingPass = """
    VIETJET AIR
    BOARDING PASS / THẺ LÊN TÀU BAY
    NGUYEN/VAN A MR
    Chuyến bay VJ123  SGN → HAN
    Ngày bay 12/09/2026
    Giờ khởi hành 06:15
    Ghế 12A   Cửa 5
    Mã đặt chỗ ABC123
    """

  static let vietnamAirlinesFutureBoardingPass = """
    Vietnam Airlines
    Thẻ lên máy bay / Boarding pass
    Chuyến bay VN 245
    Khởi hành 2026-10-20 08:00
    Gate 12  Seat 23C
    """

  static let busTicket = """
    FUTA Bus Lines
    Vé xe khách
    Mã vé FT-882211
    Tuyến: TP.HCM - Đà Lạt
    Giờ khởi hành: 22:30 01/10/2026
    Số ghế: B12
    Giá vé 290.000đ
    """

  static let randomChat = """
    Minh
    Mai 7h đi cà phê không?
    Ok nhé, hẹn 12/09 nha
    Về nhà rồi gọi lại
    Đã xem
    """

  static let bankPromo = """
    Vietcombank
    Ưu đãi tháng 10: giảm 50.000đ khi mua sắm
    Áp dụng đến 31/10/2026
    """
}
