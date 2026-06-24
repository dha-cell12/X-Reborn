# Lộ trình phát triển InstanceX (Crane-like Features)

Dưới đây là kế hoạch 5 giai đoạn để biến InstanceX thành một giải pháp quản lý container đầy đủ tính năng như Crane.

## 1. Nâng cấp cơ chế cô lập dữ liệu (Enhanced Shim Isolation)
*   **Mục tiêu:** Đảm bảo sự cô lập tuyệt đối giữa các vùng chứa dữ liệu.
*   **Hành động:**
    *   Mở rộng `ContainerShim` để hook thêm `NSUserDefaults` (thông qua `CFPreferences`) và `NSURLCache`.
    *   Hook các hàm C cấp thấp: `open`, `stat`, `access`, `rename`, `unlink` để thực hiện redirect triệt để mọi truy cập filesystem ngoài `NSHomeDirectory`.
    *   Cô lập hệ thống Database (như Accounts, Contacts) nếu ứng dụng có yêu cầu.

## 2. Định tuyến thông báo thông minh (Notification Routing)
*   **Mục tiêu:** Hỗ trợ thông báo riêng biệt cho từng tài khoản/instance.
*   **Hành động:**
    *   Hook vào `BBServer` (BulletinBoard) để đính kèm `containerID` vào metadata của mỗi thông báo.
    *   Sửa đổi trình xử lý nhấn thông báo trong SpringBoard để tự động chuyển container hoặc kích hoạt đúng instance tương ứng.

## 3. Xây dựng ứng dụng quản lý (Management UI)
*   **Mục tiêu:** Cung cấp giao diện đồ họa chuyên nghiệp để quản lý các vùng chứa.
*   **Hành động:**
    *   Phát triển một ứng dụng Manager độc lập hỗ trợ:
        *   Tạo, xóa, đổi tên và tùy chỉnh icon cho từng container.
        *   Tính năng **Backup & Restore**: Nén thư mục container thành file `.zip`.
        *   Bảo mật: Hỗ trợ FaceID/TouchID hoặc mật khẩu cho từng vùng chứa.

## 4. Ổn định hóa vòng đời ứng dụng (Lifecycle Stability)
*   **Mục tiêu:** Cải thiện độ ổn định và khả năng đa nhiệm.
*   **Hành động:**
    *   Thay thế việc gọi `posix_spawn` trực tiếp bằng cách tích hợp sâu vào `FrontBoard` (FBS) và `SBApplication`.
    *   Sử dụng các API hệ thống để iOS tự quản lý tài nguyên, giúp giảm thiểu việc app bị kill đột ngột.

## 5. Tối ưu đa nhiệm iPad (Parallel Multitasking)
*   **Mục tiêu:** Tận dụng tối đa khả năng của iPadOS.
*   **Hành động:**
    *   Cải thiện `InstanceLayout` để tương thích hoàn toàn với **Stage Manager**.
    *   Hỗ trợ IPC (Inter-Process Communication) để đồng bộ clipboard hoặc kéo thả dữ liệu giữa các cửa sổ.
