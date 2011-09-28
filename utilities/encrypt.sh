#!/sbin/sh
# Script to manage the encrypted partitions v.0.1
# author: nobodyAtall @ xda 
# usage: encrypt.sh <command> <partition>
# commands: migrate, mount, umount, update_system, passwd
# partitions: data, sdcard

# Variables
LOOPDEV_DATA=/dev/block/loop1
LOOPDEV_SDCARD=/dev/block/loop2
MAPPERDEV_DATA=/dev/mapper/data-enc
MAPPERDEV_SDCARD=/dev/mapper/sdcard-enc
MOUNTPOINT_DATA=/data-enc
MOUNTPOINT_SDCARD=/sdcard-enc

migrate()
{
	PASSWORD=`/sbin/luksunlock`
	#echo $PASSWORD
	if [ "$1" == "data" ]; then
		# Prepare encrypted partition for /data
		echo "Preparing encrypted partition for /data..."
		umount_enc data
		mount /data > /dev/null 2>&1
		DATASIZE=`df -m|grep data|grep mtd|awk '{print $2}'|sed -e 's/\..*//'`
		let "DATASIZE=$DATASIZE-15"
		echo $DATASIZE
		dd if=/dev/zero of=/sdcard/data-enc.img bs=1M count=$DATASIZE
		losetup $LOOPDEV_DATA /sdcard/data-enc.img
		echo $PASSWORD | cryptsetup -q luksFormat -c aes-plain $LOOPDEV_DATA
		echo $PASSWORD | cryptsetup luksOpen $LOOPDEV_DATA data-enc
		if [ "$?" -ne "0" ]; then
	  		return 1
		fi
		mkfs.ext2 $MAPPERDEV_DATA
		mkdir -p $MOUNTPOINT_DATA
		mount -t ext2 -o rw,noatime,nodiratime $MAPPERDEV_DATA $MOUNTPOINT_DATA
		if [ "$?" -ne "0" ]; then
	  		return 2
		fi
		# Copy existing /data partition to the encrypted one
		echo "Copying files from /data/..."
		cp -pr /data/* $MOUNTPOINT_DATA/
		umount_enc data
		rm -rf /data/*
		mv /sdcard/data-enc.img /data/
		update_system data
	elif [ "$1" == "sdcard" ]; then
		# Prepare encrypted partition for /sdcard
		echo "Preparing encrypted partition for sdcard..."
		umount_enc sdcard
		mount /sdcard > /dev/null 2>&1
		SDCARDSIZE=`df -m|grep sdcard|awk '{print $2}'|sed -e 's/\..*//'`
		rm -rf /sdcard/*
		dd if=/dev/zero of=/sdcard/sdcard-enc.img bs=1M count=$SDCARDSIZE
		losetup $LOOPDEV_SDCARD /sdcard/sdcard-enc.img
		echo $PASSWORD | cryptsetup -q luksFormat -c aes-plain $LOOPDEV_SDCARD
		echo $PASSWORD | cryptsetup luksOpen $LOOPDEV_SDCARD sdcard-enc
		if [ "$?" -ne "0" ]; then
	  		return 1
		fi
		mkfs.ext2 $MAPPERDEV_SDCARD
		mkdir -p $MOUNTPOINT_SDCARD
		mount -t ext2 -o rw,noatime,nodiratime $MAPPERDEV_SDCARD $MOUNTPOINT_SDCARD
		if [ "$?" -ne "0" ]; then
	  		return 2
		fi
		update_system sdcard
	fi
	echo "Done!"
}

mount_enc()
{
	PASSWORD=`/sbin/luksunlock`
	#echo $PASSWORD
	if [ "$1" == "data" ]; then
		echo "Mounting encrypted /data..."
		umount_enc data
		mount /data > /dev/null 2>&1
		losetup $LOOPDEV_DATA /data/data-enc.img
		echo $PASSWORD | cryptsetup luksOpen $LOOPDEV_DATA data-enc
		if [ "$?" -ne "0" ]; then
	  		return 1
		fi
		mkdir -p $MOUNTPOINT_DATA
		mount -t ext2 -o rw,noatime,nodiratime $MAPPERDEV_DATA $MOUNTPOINT_DATA
		if [ "$?" -ne "0" ]; then
	  		return 2
		fi
	elif [ "$1" == "sdcard" ]; then
		echo "Mounting encrypted sdcard..."
		umount_enc sdcard
		losetup $LOOPDEV_SDCARD /sdcard/sdcard-enc.img
		echo $PASSWORD | cryptsetup luksOpen $LOOPDEV_SDCARD sdcard-enc
		if [ "$?" -ne "0" ]; then
	  		return 1
		fi
		mkdir -p $MOUNTPOINT_SDCARD
		mount -t ext2 -o rw,noatime,nodiratime $MAPPERDEV_SDCARD $MOUNTPOINT_SDCARD
		if [ "$?" -ne "0" ]; then
	  		return 2
		fi
	fi
	echo "Done!"
}

umount_enc()
{
	if [ "$1" == "data" ]; then
		echo "Unmounting encrypted /data..."
		umount $MOUNTPOINT_DATA > /dev/null 2>&1
		cryptsetup luksClose data-enc > /dev/null 2>&1
		losetup -d $LOOPDEV_DATA > /dev/null 2>&1
	elif [ "$1" == "sdcard" ]; then
		echo "Unmounting encrypted sdcard..."
		umount $MOUNTPOINT_SDCARD > /dev/null 2>&1
		cryptsetup luksClose sdcard-enc > /dev/null 2>&1
		losetup -d $LOOPDEV_SDCARD > /dev/null 2>&1
	fi
}

update_system()
{
	if [ "$1" == "data" ]; then
		REPLACE_STRING="\n\
    # Encryption by nobodyAtall\n\
    mkdir \/data-enc 0771 system system\n\
    mount yaffs2 mtd@userdata \/data-enc nosuid nodev\n\
    insmod \/system\/lib\/modules\/dm-mod.ko\n\
    insmod \/system\/lib\/modules\/dm-crypt.ko\n\
    exec \/system\/xbin\/losetup \/dev\/block\/loop1 \/data-enc\/data-enc.img\n\
    exec \/system\/xbin\/luksunlock\n\
    exec \/system\/bin\/sh \/init.encrypt.sh"
    
		mount /system > /dev/null 2>&1
		if [ -f /system/bin/ramdisk.tar ]
		then
			rm -rf /tmp/ramdisk_encrypt
			mkdir -p /tmp/ramdisk_encrypt && cd /tmp/ramdisk_encrypt && tar -xf /system/bin/ramdisk.tar
			grep 'Encryption by nobodyAtall' init.rc > /dev/null 2>&1
			if [ "$?" -ne "0" ]; then
				echo "Updating ramdisk..."
				cp -pr /system/bin/ramdisk.tar /system/bin/ramdisk.tar.bak
				sed -i -e "s/\(mount yaffs2 mtd@userdata.*\)/\# \1 $REPLACE_STRING/" init.rc
				echo "#!/system/bin/sh" > init.encrypt.sh
				echo "/system/bin/e2fsck -y /dev/mapper/data-enc" >> init.encrypt.sh
				echo "/system/xbin/mount -t ext2 -o rw,noatime,nodiratime /dev/mapper/data-enc /data" >> init.encrypt.sh
				tar -cf /system/bin/ramdisk.tar *
			else
				echo "Ramdisk was already updated!"
			fi	
		else
			echo "Could not find ramdisk!"
			return 1
		fi
		# We also need the kernel modules and luksunlock, to be copied to /system
		if [ ! -f /system/lib/modules/dm-mod.ko ]
		then
			echo "Copying kernel modules..."
			cp -pr /etc/modules/dm-mod.ko /system/lib/modules/
			cp -pr /etc/modules/dm-crypt.ko /system/lib/modules/
		fi
		echo "Copying luksunlock..."
		cp -pr /sbin/luksunlock_unlock /system/xbin/luksunlock
		mkdir -p /system/usr/res/
		cp -pr /res/images/padlock.png /system/usr/res/padlock.png
		echo "Copying cryptsetup..."
		cp -pr /sbin/cryptsetup /system/xbin/cryptsetup
		chmod 755 /system/xbin/luksunlock /system/xbin/cryptsetup
		
	elif [ "$1" == "sdcard" ]; then
		#TODO
		echo "Updating ramdisk for sdcard is not implemented"
	fi
}

update_passwd()
{
	if [ "$1" == "data" ]; then
		mount /data > /dev/null 2>&1
		umount_enc data
		losetup $LOOPDEV_DATA /data/data-enc.img
		# Find out the last key (which will be deleted)
		DELETEKEY=`cryptsetup luksDump $LOOPDEV_DATA |grep Slot|grep ENABLED |tail -n 1 |awk {'print $3'} |sed 's/://'`
		PASSWORD_OLD=`/sbin/luksunlock`
		echo $PASSWORD_OLD | cryptsetup luksOpen $LOOPDEV_DATA data-enc
		if [ "$?" -ne "0" ]; then
			echo "Invalid password"
			umount_enc data
			return 2
		fi
		cryptsetup luksClose data-enc
		PASSWORD_NEW=`/sbin/luksunlock`
		PASSWORD_NEW_VERIFY=`/sbin/luksunlock`
		if [ "$PASSWORD_NEW" == "$PASSWORD_NEW_VERIFY" ]; then
			echo "New and verify passwords match!"
			#echo -e "${PASSWORD_OLD}\n${PASSWORD_NEW}\n${PASSWORD_NEW_VERIFY}"
			echo -e "${PASSWORD_OLD}\n${PASSWORD_NEW}\n${PASSWORD_NEW_VERIFY}" | cryptsetup luksAddKey $LOOPDEV_DATA
			if [ "$?" -ne "0" ]; then
				echo "Failed to create new password!"
				umount_enc data
				return 3
			fi
			echo $PASSWORD_NEW | cryptsetup luksKillSlot $LOOPDEV_DATA $DELETEKEY
			if [ "$?" -ne "0" ]; then
				echo "Failed to delete previous password!"
				umount_enc data
				return 4
			fi
		else
			echo "Passwords are not the same!"
			umount_enc data
			return 5
		fi
	elif [ "$1" == "sdcard" ]; then
		#TODO
		echo "Updating ramdisk for sdcard is not implemented"
	fi
	
	umount_enc data
}

if [ "$1" == "migrate" ] ; then
	migrate $2
elif [ "$1" == "mount" ] ; then
	mount_enc $2
elif [ "$1" == "umount" ] ; then
	umount_enc $2
elif [ "$1" == "update_system" ] ; then
	update_system $2
elif [ "$1" == "passwd" ] ; then
	update_passwd $2
fi

