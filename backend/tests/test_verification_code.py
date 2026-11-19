"""D-311: verification codes found by a fixed rule (never the LLM), recent mail only."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services.verification_code import find, recent_code


@pytest.mark.parametrize("subject, body, code", [
    ("Mã xác minh Google", "G-482913 là mã xác minh của bạn.", "482913"),
    ("Your verification code", "Use 739204 to sign in. It expires in 10 minutes.", "739204"),
    ("Đăng nhập", "Mã OTP của quý khách là 5531. Không chia sẻ mã này.", "5531"),
    ("Shopee", "Ma xac nhan cua ban: 408812", "408812"),
    ("Zalo", "Your code: X7K2PQ", "X7K2PQ"),
    ("123456 là mã đăng nhập Facebook của bạn", "", "123456"),
])
def test_codes(subject, body, code):
    assert find(subject, body) == code


@pytest.mark.parametrize("subject, body", [
    ("Họp tổ chiều thứ Sáu", "Em ơi, 15:00 thứ Sáu em dự họp được không?"),
    ("Hóa đơn tháng 11", "Tổng tiền 250000 đồng. Cảm ơn quý khách."),          # a number but no keyword
    ("Mã giảm giá", "Ưu đãi năm 2026 dành cho bạn"),                           # a year is not a code
    ("Gọi lại", "Mã vùng +84 901234567"),                                       # phone digits are > 8 / glued
    ("Đơn hàng", "Mã đơn hàng: https://shop.vn/o/1234567"),                     # inside a link
    ("Shopee", "Mã đơn hàng 24111812 đã được giao."),                           # an order number
    ("Khuyến mãi", "Nhập mã giảm giá SALE2026 khi thanh toán"),                 # a coupon
])
def test_no_code(subject, body):
    assert find(subject, body) is None


def test_old_mail_shows_no_code():
    now = datetime(2026, 11, 18, 2, 0, tzinfo=UTC)
    assert recent_code("Mã xác minh", "482913", now - timedelta(minutes=30), now, 60) == "482913"
    assert recent_code("Mã xác minh", "482913", now - timedelta(minutes=61), now, 60) is None
