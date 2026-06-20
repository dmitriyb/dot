# Linux-specific functions
# Only useful on Linux systems

# Write iso file to sd card
function iso2sd
    if test (count $argv) -ne 2
        echo "Usage: iso2sd <input_file> <output_device>"
        echo "Example: iso2sd ~/Downloads/ubuntu-25.04-desktop-amd64.iso /dev/sda"
        echo ""
        echo "Available SD cards:"
        lsblk -d -o NAME | grep -E '^sd[a-z]' | awk '{print "/dev/"$1}'
    else
        sudo dd bs=4M status=progress oflag=sync if=$argv[1] of=$argv[2]
        sudo eject $argv[2]
    end
end

# Format an entire drive for a single partition using ext4
function format-drive
    if test (count $argv) -ne 2
        echo "Usage: format-drive <device> <name>"
        echo "Example: format-drive /dev/sda 'My Stuff'"
        echo ""
        echo "Available drives:"
        lsblk -d -o NAME -n | awk '{print "/dev/"$1}'
    else
        echo "WARNING: This will completely erase all data on $argv[1] and label it '$argv[2]'."
        read -P "Are you sure you want to continue? (y/N): " confirm
        if string match -qi y $confirm
            sudo wipefs -a $argv[1]
            sudo dd if=/dev/zero of=$argv[1] bs=1M count=100 status=progress
            sudo parted -s $argv[1] mklabel gpt
            sudo parted -s $argv[1] mkpart primary ext4 1MiB 100%
            if string match -q "*nvme*" $argv[1]
                sudo mkfs.ext4 -L $argv[2] "$argv[1]p1"
            else
                sudo mkfs.ext4 -L $argv[2] "$argv[1]1"
            end
            sudo chmod -R 777 "/run/media/$USER/$argv[2]"
            echo "Drive $argv[1] formatted and labeled '$argv[2]'."
        end
    end
end
