# SUSE's openQA tests
#
# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: mkosi-initrd
# Summary: Ensure system is still booting after
# dracut is replaced with mkosi-initrd and
# initrd is regenerated
# Maintainer: Benjamin Brunner <bbrunner@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;
use serial_terminal 'select_serial_terminal';
use utils 'clear_console';
use utils qw(zypper_call);
use power_action_utils qw(power_action);
use version_utils 'is_sle';

sub run {
    my ($self) = @_;
    my $initrd_check = '/usr/lib/module-init-tools/lsinitrd-quick /boot/initrd |\
      if grep "lib/dracut" > /dev/null; \
      then echo "Initrd created by dracut"; \
      else echo "Initrd created by mkosi"; fi';

    select_console('root-console');

    my $kver = script_output("uname -r");

    script_run("echo 'dracut-initrd:' >> /boot_cmp.log");
    script_run("ls -lh /boot/initrd-$kver >> /boot_cmp.log");
    script_run('journalctl --no-pager -b -p 3 -o cat > /boot_dracut.log');

    # disable local repos
    zypper_call 'mr -dF -l';

    zypper_call 'mr -k --all';
    zypper_call '--gpg-auto-import-keys ref';

    clear_console;
    assert_script_run($initrd_check);
    assert_screen('initrd-dracut');
    script_run("echo 'INITRD_GENERATOR=mkosi-initrd' >> /etc/sysconfig/bootloader");
    zypper_call 'in mkosi-initrd';

    # Workaround, remove unneeded files
    type_string("cat >> /etc/mkosi-initrd/mkosi.conf <<EOF
[Content]
RemoveFiles=
    /usr/lib/tmpfiles.d/fs-usr-local.conf
EOF
");
    assert_script_run("cat /etc/mkosi-initrd/mkosi.conf");
    zypper_call 'in --force mkosi-initrd';
    clear_console;
    assert_script_run($initrd_check);
    assert_screen('initrd-mkosi');

    power_action('reboot', textmode => 1);
    $self->wait_boot(bootloader_time => 200);

    select_console('root-console');
    script_run('journalctl --no-pager -b -p 3 -o cat > /boot_mkosi.log');
    script_run("echo 'mkosi-initrd:' >> /boot_cmp.log");
    script_run("ls -lh /boot/initrd-$kver >> /boot_cmp.log");
    script_run("echo 'Diff Boot (journalctl -b -p 3):' >> /boot_cmp.log");
    script_run('diff /boot_dracut.log /boot_mkosi.log >> /boot_cmp.log');
    upload_logs('/boot_cmp.log');

    select_serial_terminal;
}

sub test_flags {
    return {milestone => 1};
}

1;
