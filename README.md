### Usage:
`./virt-backup.sh <base_path> <vm_name> <keep_months> <recipient_email> <sender_email> [force] [exclude_disk]`
### Example:
`./virt-backup.sh /backups web01 3 admin@company.com backup@company.com force sda`

### Additional info
 Get all backups info metadata:
```
docker run --rm \
-v /run:/run \
-v /var/tmp:/var/tmp \
-v /etc/libvirt/qemu/nvram:/etc/libvirt/qemu/nvram \
-v /usr/share/OVMF:/usr/share/OVMF \
-v /BACKUPS_ROOT_MOUNTPOINT:/backups \
ghcr.io/abbbi/virtnbdbackup:master \
virtnbdrestore -i /backups/PATH_TO_VM/MONTH -o dump
```
Verify integrity of backups:
```
docker run --rm \
-v /run:/run \
-v /var/tmp:/var/tmp \
-v /etc/libvirt/qemu/nvram:/etc/libvirt/qemu/nvram \
-v /usr/share/OVMF:/usr/share/OVMF \
-v /BACKUPS_ROOT_MOUNTPOINT:/backups \
ghcr.io/abbbi/virtnbdbackup:master \
virtnbdrestore -i /backups/PATH_TO_VM/MONTH -o verify
```

* where `/BACKUPS_ROOT_MOUNTPOINT` is your backups root location e.g. `/mnt/backups`
* where `PATH_TO_VM` is VM name e.g. `sec-fs`
* where `MONTH` is your month date in format of mmyyyy e.g. `072025`
