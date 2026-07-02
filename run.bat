@echo off
:: Убедись, что путь к qemu-system-i386.exe правильный (или просто qemu-system-i386, если он в PATH)
echo Запускаем QEMU...
"C:\Program Files\qemu\qemu-system-i386.exe" -drive format=raw,file=build\os-image.bin,if=floppy -drive format=raw,file=build\disk.img,if=ide,index=0,media=disk -boot a -cpu Haswell
pause