# Bằng chứng nghiệm thu hạ tầng k3s (Issue #1)

Ngày thu thập: 16/11/2026

## 1. Trạng thái node

Lệnh chạy trên máy host: `kubectl get nodes -o wide`

```text
NAME         STATUS   ROLES           AGE   VERSION        INTERNAL-IP       EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION             CONTAINER-RUNTIME
k3s-agent    Ready    worker          82m   v1.37.2+k3s1   192.168.174.102   <none>        Ubuntu 26.04.1 LTS   7.0.0-43-generic (amd64)   containerd://2.3.7-k3s1
k3s-server   Ready    control-plane   83m   v1.37.2+k3s1   192.168.174.101   <none>        Ubuntu 26.04.1 LTS   7.0.0-43-generic (amd64)   containerd://2.3.7-k3s1
```

## 2. Kiểm tra SSH giữa các VM

Lệnh chạy trên host: `ssh devops@192.168.174.101 "ssh devops@192.168.174.102 'hostname && ip -4 addr show | grep 192.168'"`

```text
k3s-agent
    inet 192.168.174.102/24 brd 192.168.174.255 scope global ens33
```

Lệnh SSH sử dụng `BatchMode=yes` và hoàn tất thành công, xác nhận kết nối key-based từ host tới server và từ server tới agent.

## 3. Chạy lại Ansible và kiểm tra idempotence

Chạy playbook `~/ansible/deploy-k3s.yml` trên `k3s-server`. Lượt chạy trước đó cài đặt không báo thay đổi ở các tác vụ cài đặt, nhưng tác vụ kiểm tra `kubectl get nodes` bị Ansible đánh dấu `changed` mặc định dù chỉ đọc. Playbook trong repo đã đặt `changed_when: false` cho tác vụ kiểm tra; lượt xác minh sau chỉnh sửa được chạy bằng cùng inventory và playbook đó.

Kết quả lượt xác minh:

```text
PLAY RECAP *********************************************************************
k3s-agent                  : ok=2    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
k3s-server                 : ok=8    changed=0    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

`changed=0` trên cả hai host; không có host unreachable hoặc task failed.
