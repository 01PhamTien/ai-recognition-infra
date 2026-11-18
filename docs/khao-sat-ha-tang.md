# Báo cáo khảo sát máy vật lý & kiến trúc hạ tầng (TV4 - Định)

Ngày khảo sát: 16/11/2026

## 1. Thông số máy host Windows

| Thông số | Kết quả |
| :--- | :--- |
| Hệ điều hành | Windows 11 Home Single Language |
| CPU | 12th Gen Intel(R) Core(TM) i5-12450H |
| Luồng xử lý logic | 12 |
| RAM vật lý | 15.6 GB |
| Dung lượng ổ D còn trống | 135.8 GB |
| VMware Workstation | 17.6.3 build-24583834 |

**Ảo hóa:** Các VM VMware đang chạy và được kiểm tra trong báo cáo này. Tuy nhiên, truy vấn WMI trên Windows trả về `VirtualizationFirmwareEnabled=False`, `VMMonitorModeExtensions=False` và `HypervisorPresent=True`. Vì vậy, trạng thái bật VT-x/AMD-V trong BIOS/UEFI và việc Hyper-V có ảnh hưởng đến VMware hay không chưa thể xác nhận chỉ từ khảo sát này; cần kiểm tra trực tiếp trong BIOS/UEFI và VMware trước khi dựng lại VM.

## 2. Hai VM và quy hoạch mạng

Thông số CPU, RAM, dung lượng đĩa, OS, IP và gateway dưới đây được kiểm tra trực tiếp trên từng VM. Dung lượng đĩa là kích thước virtual disk; phân vùng root hiện mới dùng LVM 14 GB.

| VM | Hostname | Vai trò | OS | CPU | RAM | Virtual disk / root | IP | Gateway |
| :--- | :--- | :--- | :--- | :---: | :---: | :--- | :--- | :--- |
| VM1 | `k3s-server` | Control plane + Ansible node | Ubuntu 26.04.1 LTS | 2 vCPU | 2.5 GiB | 30 GB / 14 GB | `192.168.174.101` | `192.168.174.2` |
| VM2 | `k3s-agent` | Worker (`worker`) | Ubuntu 26.04.1 LTS | 2 vCPU | 2.5 GiB | 30 GB / 14 GB | `192.168.174.102` | `192.168.174.2` |

```text
[Windows host]
      |
      +-- VMware NAT: 192.168.174.0/24, gateway 192.168.174.2
              |
              +-- k3s-server (control-plane, 192.168.174.101)
              |       |
              |       +-- Ansible quản lý k3s-agent
              |
              +-- k3s-agent (worker, 192.168.174.102)
```

## 3. Trạng thái và lưu ý vận hành

- Hai node đang `Ready`, cùng phiên bản k3s `v1.37.2+k3s1`; chi tiết lệnh được lưu tại [bằng chứng nghiệm thu](./bang-chung-nghiem-thu.md).
- Kết nối SSH bằng key từ host tới server và từ server tới agent đã được kiểm tra thành công.
- `sshd -T` trả về `permitrootlogin prohibit-password`; điều này vẫn cho phép khả năng đăng nhập root bằng public key, nên không thể kết luận root login đã bị khóa hoàn toàn.
- UFW đang `inactive` trên cả hai VM. Cấu hình firewall và việc giới hạn Kubernetes API khỏi Internet chưa được xác minh; cần hoàn tất trước khi coi đây là cấu hình bảo mật nghiệm thu.
- Có thể khởi động/tắt VM trong VMware Workstation (`Power On` / `Shut Down Guest`); trong guest có thể dùng `sudo shutdown -h now`. Truy cập server bằng `ssh devops@192.168.174.101`.

## 4. Giới hạn và việc cần chốt

Đây là khảo sát trạng thái hiện tại, không xác nhận phương án đã được người phụ trách duyệt trước khi tạo VM. Issue #1 yêu cầu báo cáo tài nguyên và chốt phương án trước khi triển khai; cần lưu xác nhận của người phụ trách vào PR. Chưa xác minh cổng 6443 có thể truy cập từ Internet hay không.
