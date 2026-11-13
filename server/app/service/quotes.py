"""Motivation quotes (R49). Built-in list for now; Gemini is plugged in later and must fall
back to this list whenever it fails, so R5 never errors."""

import random

# (text, author); author None = written for Recolly.
FALLBACK: dict[str, list[tuple[str, str | None]]] = {
    "general": [
        ("Hành trình vạn dặm bắt đầu từ một bước chân.", "Lão Tử"),
        ("Không có việc gì khó, chỉ sợ lòng không bền.", "Hồ Chí Minh"),
        ("Học, học nữa, học mãi.", "V. I. Lenin"),
        ("Thành công là tổng của những nỗ lực nhỏ, lặp lại ngày qua ngày.", "Robert Collier"),
        ("Hôm nay chỉ cần tốt hơn hôm qua một chút là đủ.", None),
    ],
    "deadline": [
        ("Chia việc lớn thành từng khối nhỏ, rồi làm khối đầu tiên ngay bây giờ.", None),
        ("Deadline không đáng sợ bằng việc chưa bắt đầu.", None),
        ("25 phút tập trung, 5 phút nghỉ: lặp lại cho đến khi xong.", None),
        ("Làm xong còn hơn làm hoàn hảo; sửa sau vẫn kịp.", None),
    ],
    "sleep": [
        ("Ngủ đủ giấc cũng là ôn bài: não ghi nhớ kiến thức trong lúc ngủ.", None),
        ("Dù là sư tử, gấu hay sói, bạn vẫn cần ít nhất 7 tiếng ngủ.", None),
        ("Cất điện thoại sớm hơn 30 phút, sáng mai bạn sẽ tỉnh táo hơn.", None),
        ("Thức khuya thêm một giờ thường lấy mất của bạn nhiều hơn một giờ tập trung.", None),
    ],
    "progress": [
        ("Bạn vừa hoàn thành thêm một khối học. Giữ nhịp này nhé!", None),
        ("Từng bước nhỏ đều đặn sẽ đưa bạn đi rất xa.", None),
        ("Xong một việc rồi! Nghỉ 5 phút, uống nước rồi tiếp tục.", None),
        ("Tiến bộ quan trọng hơn hoàn hảo.", None),
    ],
}


def random_quote(context: str = "general") -> dict[str, str | None]:
    text, author = random.choice(FALLBACK[context])
    return {"text": text, "author": author, "source": "fallback", "context": context}
