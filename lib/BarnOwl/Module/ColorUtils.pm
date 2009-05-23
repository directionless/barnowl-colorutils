# -*- mode: cperl; cperl-indent-level: 4; indent-tabs-mode: nil -*-
# Colors module.
use strict;
use warnings;

package BarnOwl::Module::ColorUtils;

=head1 NAME

BarnOwl::Module::ColorUtils

=head1 DESCRIPTION

This module implements easy to use color suppot for barnowl.

=cut

use Getopt::Long;
################################################################################
## Color state.
################################################################################
our @colorList;
our %currentColorMap;
our %savedColorMap;
our %mode2Protocol = ('zephyr' => 'zephyr',
		      'zephyr-personal' => 'zephyr',
		      'aim' => 'aim',
		      'jabber' => 'jabber',
                      'irc' => 'IRC',
		      'loopback' => 'loopback');


################################################################################
#Run this on start and reload. Adds styles, sets style to start.
################################################################################
my $config_dir = BarnOwl::get_config_dir();

sub onStart {
    %currentColorMap = ();
    %savedColorMap = ();
    genColorList();
    bindings_Color();
    cmd_load();
}
$BarnOwl::Hooks::startup->add(\&onStart);

sub genColorList() {
   @colorList = ('black','red','green','yellow',
                  'blue','magenta','cyan','white');
    if ( *BarnOwl::getnumcolors{CODE} ) {
        for (my $i = 8; $i < BarnOwl::getnumcolors(); $i++) {
            push(@colorList,$i);
        }
    }
}

################################################################################
#Register BarnOwl commands and default keybindings.
################################################################################
sub bindings_Color
{
    # Commands
    BarnOwl::new_command(
        setcolor => \&cmd_setcolor,
        {
            summary => "Change the color for this sender (personals) or class/muc (or instance if zephyr -c message)",
            usage   => "setcolor [-i] [-b] [color]",
            description => "Sets the foreground (or background) color for this kind of message.\n\n"
              . "The following options are available:\n\n"
              . " -i    Set the color for this instance of this zephyr class.\n\n"
              . " -b    Sets the background color instead of the foreground color.\n\n"
              . "color may be any of the colors listed in `:show color'; if using a 256-color\n"
              . "terminal, you may also use an HTML-style color code, #rrggbb, which will\n"
              . "be matched to the closest color approximation in a 6x6x6 colorcube.\n"
              . "The following special values are also allowed:\n"
              . "  default    uncolors the message\n"
              . "  restore    restores the last saved color for this message\n"
              . "If no color is specified, the current color is displayed.\n"
        }
    );
    BarnOwl::new_command(
        loadcolors => \&cmd_load,
        {
            summary => "Load color filter definitions from disk.",
            usage   => "loadcolors"
        }
    );
    BarnOwl::new_command(
        savecolors => \&cmd_save,
        {
            summary => "Save active color filter definitions to disk.",
            usage   => "savecolors"
        }
    );

    # Key Bindings
    owl::command('bindkey recv "c" command start-command setcolor ');
}


################################################################################
## Loading function
################################################################################
sub createFilters($) {
    # Prepare the color filters.
    my $fgbg = shift;
    return unless (grep(/^[fb]g$/, $fgbg));
    my $currentView = owl::getview();

    my %workingColorMap = %{ $currentColorMap{$fgbg} };

    foreach my $color (@colorList) {
        my @strs;

        #######################################################################
        my $mode = 'zephyr';
        {
            my @class = ();
            my @classInst = ();

            foreach my $c (sort keys %{ $workingColorMap{$mode} }) {
                my $c_esc = $c;
                $c_esc =~ s/([+*])/\\$1/g;
                my @instances = (sort keys %{ $workingColorMap{$mode}{$c} });
                my $cHasStar = grep(/\*/, @instances);

                if ($cHasStar && @instances == 1) {
                    # Collect classes that are only globally colored.
                    push(@class, $c_esc) if ($workingColorMap{$mode}{$c}{'*'} eq $color);
                } else {
                    # Collect classes that have varying color for instances.
                    if ($cHasStar && $workingColorMap{$mode}{$c}{'*'} eq $color) {
                        my @cInstances;
                        foreach my $i (@instances) {
                            next if (($i eq '*') || ($workingColorMap{$mode}{$c}{$i} eq $color));
                            $i =~ s/([+*])/\\$1/g;
                            push(@cInstances, $i);
                        }
                        push(@classInst, 'class ^'.$c_esc.'(.d)*$ and not instance ^('.join('|',@cInstances).')(.d)*$') if (@cInstances);
                    } else {
                        my @cInstances;
                        foreach my $i (@instances) {
                            next if (($i eq '*') || ($workingColorMap{$mode}{$c}{$i} ne $color));
                            $i =~ s/([+*])/\\$1/g;
                            push(@cInstances, $i);
                        }
                        push(@classInst, 'class ^'.$c_esc.'(.d)*$ and instance ^('.join('|',@cInstances).')(.d)*$') if (@cInstances);
                    }
                }
            }

            # Join the collected classes into one big filter.
            if (scalar(@class) || scalar(@classInst)) {
                push(@strs,
                     '( type ^'.$mode2Protocol{$mode}.'$ and ( '
                     . ((scalar(@class)) ? 'class ^('.join('|',@class).')(.d)*$ ' : '')
                     . ((scalar(@class) && scalar(@classInst)) ? 'or ' : '')
                     . ((scalar(@classInst)) ? '( '.join(' ) or ( ', @classInst).' ) ' : '')
                     . ' ) )');
            }
        }
        #######################################################################
        $mode = 'zephyr-personal';
        {
            my $senders = '';
            my $count = 0;
            foreach my $sender (sort keys %{ $workingColorMap{$mode} }) {
                next if ($workingColorMap{$mode}{$sender} ne $color);
                $sender =~ s/([+*])/\\$1/g;
                $count++;
                $senders .= ($senders eq "") ? $sender : "|$sender";
            }
            if ($count) {
                push(@strs,
                     '( type ^'.$mode2Protocol{$mode}.'$ and ( ( class ^message$ and instance ^personal$ ) or class ^login$ )'
                     . ' and ( not body ^CC )'
                     . ' and ( sender ^('.$senders.')$ or recipient ^('.$senders.')$ ) )');
            }
        }
        #######################################################################
        $mode = 'aim';
        {
            my $senders = "";
            my $count = 0;
            foreach my $sender (sort keys %{ $workingColorMap{$mode} }) {
                next if ($workingColorMap{$mode}{$sender} ne $color);
                $sender =~ s/([+*])/\\$1/g;
                $count++;
                $senders .= ($senders eq "") ? $sender : "|$sender";
            }
            if ($count) {
                push(@strs,
                     '( type ^'.$mode2Protocol{$mode}.'$'
                     . ' and ( sender ^('.$senders.')$ or recipient ^('.$senders.')$ ) )');
            }
        }
        #######################################################################
        $mode = 'jabber';
        {
            my $senders = "";
            my $count = 0;
            foreach my $sender (sort keys %{ $workingColorMap{$mode} }) {
                next if ($workingColorMap{$mode}{$sender} ne $color);
                $sender =~ s/([+*])/\\$1/g;
                $count++;
                $senders .= ($senders eq "") ? $sender : "|$sender";
            }
            if ($count) {
                push(@strs,
                     '( type ^'.$mode2Protocol{$mode}.'$'
                     . ' and ( sender ^('.$senders.')$ or recipient ^('.$senders.')$ ) )');
            }
        }
        #######################################################################
        $mode = 'irc';
        {
            my @servers = ();
            my $sCount = 0;
            foreach my $srv (sort keys %{ $workingColorMap{$mode} }) {
                my @channels = ();
                my $count = 0;
                foreach my $chan (sort keys %{ $workingColorMap{$mode}{$srv} }) {
                    next if ($workingColorMap{$mode}{$srv}{$chan} ne $color);
                    $chan =~ s/([+*])/\\$1/g;
                    push(@channels, $chan);
                    $count++;
                }
                $srv =~ s/([+*])/\\$1/g;
                if ($count) {
                    push(@servers,
                         ' ( server ^'.$srv.'$ and channel ^('.join('|',@channels).')$ )'
                     );
                    $sCount++;
                }
            }
            if ($sCount) {
                push(@strs,
                     '( type ^'.$mode2Protocol{$mode}.'$'
                       . ' and ( '. join(' or ', @servers)
                         .' ) )');
            }
        }
        #######################################################################
        $mode = 'loopback';
        {
            push(@strs, '( type ^'.$mode2Protocol{$mode}.'$ )') if (($workingColorMap{$mode} || '') eq $color);
        }
        #######################################################################

        my $filter = 'ColorUtils::'.$color.(($fgbg eq 'bg') ? '-bg' : '');
        my $filterspec = "$filter ".(($fgbg eq 'bg') ? '-b' : '-c')." $color ";
        if (scalar(@strs)) {
            BarnOwl::filter("$filterspec ( "
                           . join(' or ', @strs)
                           . ' )');
        } else {
            next if ($currentView eq $filter);
            BarnOwl::_remove_filter($filter);
        }
    }
}

sub normalize_rgb {
    my $c = shift;
    return 0 if ($c < 26);
    return 1 if ($c < 77);
    return 2 if ($c < 128);
    return 3 if ($c < 179);
    return 4 if ($c < 230);
    return 5;
}

sub find_color($$$) {
    my $r = normalize_rgb(shift);
    my $g = normalize_rgb(shift);
    my $b = normalize_rgb(shift);
    return 16 + (36 * $r) + (6 * $g) + $b;
}

sub cmd_setcolor {
    my $fgbg;
    my $inst;

    shift; #strip setcolor from argument list.
    local @ARGV = @_;
    GetOptions(
        'backgroud'  => \$fgbg,
        'instance' => \$inst,
    );

    if ((scalar @ARGV) <= 0) {
        BarnOwl::message(sprintf("The current message is colored \"%s\".\n", getColor($inst, $fgbg)));
        return;
    }
    my $color = shift @ARGV;

    if ($color =~ /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i) {
        $color = find_color(hex($1),hex($2),hex($3));
    }
    if ($color eq 'default') {
        unset($inst, $fgbg);
    } elsif ($color eq 'restore') {
        restore($inst, $fgbg);
    } else {
        die("setcolor: invalid color ($color)\n") unless grep(/$color/,@colorList);
        setColor($color, $inst, $fgbg);
    }
}

sub cmd_save {
    save('fg');
    save('bg');
    cmd_load();
}

sub cmd_load {
    load('fg');
    load('bg');
    refreshView('fg');
    refreshView('bg');
}

################################################################################
## Color toggling functions
################################################################################
sub isZPersonal {
    # Return 1 for things that would qualify a zephyr as personal.
    my $m = shift;
    return 1 if ($m->recipient ne "" and $m->recipient !~ /^@/);
    return 1 if lc($m->class) eq "login";
    return 0;
}

sub unset($$) {
    my $bInst = shift;
    my $fgbg = (shift || 0) ? 'bg' : 'fg';
    my $m = owl::getcurmsg();
    return unless $m;
    my $type = lc($m->type);
    if ($type eq 'zephyr') {
        if (isZPersonal($m)) {
            my $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
            $sender =~ s/ /./g;
            delete $currentColorMap{$fgbg}{'zephyr-personal'}{$sender};
        } else {
            my $class = lc($m->class);
            my $instance = ($bInst || ($class eq 'message')) ? lc($m->instance) : '*';
            $class =~ s/ /./g;
            $instance =~ s/ /./g;
            if ($instance eq '*') {
                $currentColorMap{$fgbg}{$type}{$class}{$instance} = 'default';
            } else {
                delete $currentColorMap{$fgbg}{$type}{$class}{$instance};
            }
        }
    } elsif ($type eq 'aim' || $type eq 'jabber') {
        my $sender = (lc($m->direction) eq 'in') ? $m->sender : $m->recipient;
        $sender = $m->recipient if ($type eq 'jabber' && lc($m->jtype) eq 'groupchat');
        $sender =~ s/ /./g;
        delete $currentColorMap{$fgbg}{$type}{$sender};
    } elsif ($type eq 'loopback') {
        delete $currentColorMap{$fgbg}{$type};
    }
    refreshView($fgbg);
}

sub setColor($$$)
{
    my $color = shift;
    my $bInst = shift;
    my $fgbg = (shift || 0) ? 'bg' : 'fg';
    my $m = owl::getcurmsg();
    return unless $m;

    my $type = lc($m->type);
    if ($type eq 'zephyr') {
	if (isZPersonal($m)) {
	    my $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
            $sender =~ s/ /./g;
	    $currentColorMap{$fgbg}{'zephyr-personal'}{$sender} = $color;
	} else {
	    my $class = lc($m->class);
	    my $instance = ($bInst || ($class eq 'message')) ? lc($m->instance) : '*';
            $class =~ s/ /./g;
            $instance =~ s/ /./g;
	    $currentColorMap{$fgbg}{$type}{$class}{$instance} = $color;
	}
    } elsif ($type eq 'aim' || $type eq 'jabber') {
	my $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
        $sender =~ s/ /./g;
	$sender = $m->recipient if ($type eq 'jabber' && lc($m->jtype) eq 'groupchat');
	$currentColorMap{$fgbg}{$type}{$sender} = $color;
    } elsif ($type eq 'irc') {
        $currentColorMap{$fgbg}{$type}{$m->server}{$m->channel} = $color;
    } elsif ($type eq 'loopback') {
	$currentColorMap{$fgbg}{$type} = $color;
    }

    refreshView($fgbg);
}

sub getColor($$)
{
    my $bInst = shift;
    my $fgbg = (shift || 0) ? 'bg' : 'fg';
    my $m = owl::getcurmsg();
    return "" unless $m;

    my $type = lc($m->type);
    if ($type eq 'zephyr') {
	if (isZPersonal($m)) {
	    my $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
            $sender =~ s/ /./g;
            if (exists($currentColorMap{$fgbg}{'zephyr-personal'}{$sender})) {
                return $currentColorMap{$fgbg}{'zephyr-personal'}{$sender};
            }
	} else {
	    my $class = lc($m->class);
	    my $instance = ($bInst || ($class eq 'message')) ? lc($m->instance) : '*';
            $class =~ s/ /./g;
            $instance =~ s/ /./g;
            if (exists($currentColorMap{$fgbg}{$type}{$class}{$instance})) {
                return $currentColorMap{$fgbg}{$type}{$class}{$instance};
            }
	}
    } elsif ($type eq 'aim' || $type eq 'jabber') {
	my $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
        $sender =~ s/ /./g;
	$sender = $m->recipient if ($type eq 'jabber' && lc($m->jtype) eq 'groupchat');
        if (exists($currentColorMap{$fgbg}{$type}{$sender})) {
            return $currentColorMap{$fgbg}{$type}{$sender};
        }
    } elsif ($type eq 'irc') {
        if (exists($currentColorMap{$fgbg}{$type}{$m->server}{$m->channel})) {
            return $currentColorMap{$fgbg}{$type}{$m->server}{$m->channel};
        }
    } elsif ($type eq 'loopback') {
        if (exists($currentColorMap{$fgbg}{$type})) {
            return $currentColorMap{$fgbg}{$type};
        }
    }
}

sub restore($$) {
    my $bInst = shift;
    my $fgbg = (shift || 0) ? 'bg' : 'fg';
    my $m = owl::getcurmsg();
    return unless $m;
    my $type = lc($m->type);
    my $oldColor;
    my $sender;
    if ($type eq 'zephyr') {
	if (isZPersonal($m)) {
	    $sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
            $sender =~ s/ /./g;
	    if ($oldColor = ($savedColorMap{$fgbg}{'zephyr-personal'}{$sender}) || '') {
		$currentColorMap{$fgbg}{'zephyr-personal'}{$sender} = $oldColor;
	    } else {
		delete $currentColorMap{$fgbg}{'zephyr-personal'}{$sender};
	    }
	} else {
	    my $class = lc($m->class);
	    my $instance = lc($m->instance);
	    $instance =
              ($bInst
		 || ($class eq 'message')
                 || ((($savedColorMap{$fgbg}{$type}{$class}{'*'} || '') eq ($currentColorMap{$fgbg}{$type}{$class}{'*'} || ''))
                     && (($savedColorMap{$fgbg}{$type}{$class}{$instance} || '') ne ($currentColorMap{$fgbg}{$type}{$class}{$instance} || ''))))
		? $instance
                  : '*';
            $class =~ s/ /./g;
            $instance =~ s/ /./g;
	    if ($oldColor = ($savedColorMap{$fgbg}{$type}{$class}{$instance} || '')) {
		$currentColorMap{$fgbg}{$type}{$class}{$instance} = $oldColor;
	    } else {
		delete $currentColorMap{$fgbg}{$type}{$class}{$instance};
	    }
	}
    } elsif ($type eq 'aim' || $type eq 'jabber') {
	$sender = lc((lc($m->direction) eq 'in') ? $m->sender : $m->recipient);
	$sender = $m->recipient if ($type eq 'jabber' && lc($m->jtype) eq 'groupchat');
        $sender =~ s/ /./g;
	if ($oldColor = ($savedColorMap{$fgbg}{$type}{$sender} || '')) {
	    $currentColorMap{$fgbg}{$type}{$sender} = $oldColor;
	} else {
	    delete $currentColorMap{$fgbg}{$type}{$sender};
	}
    } elsif ($type eq 'loopback') {

	if ($oldColor = ($savedColorMap{$fgbg}{$type} || '')) {
	    $currentColorMap{$fgbg}{$type} = $oldColor;
	} else {
	    delete $currentColorMap{$fgbg}{$type};
	}
    }

    refreshView($fgbg);
}

sub refreshView($) {
    my $fgbg = shift;
    return unless (grep(/^[fb]g$/, $fgbg));

    createFilters($fgbg);
    if ( *BarnOwl::refresh_view{CODE} ) {
        BarnOwl::refresh_view();
    } else {
        my $filter = owl::command("getview");
        my $style = owl::command("getstyle");
        owl::command("view -f $filter ".($style?"-s $style":""));
    }
}

################################################################################
## Saving/Loading functions
################################################################################
sub save($) {
    my $fgbg = shift;
    return unless (grep(/^[fb]g$/, $fgbg));

    if ($fgbg eq 'bg') {
        open(COLORS, ">$config_dir/colormap_bg");
    } else {
        open(COLORS, ">$config_dir/colormap");
    }

    my $type = 'zephyr';
    print COLORS "MODE: $type\n";
    foreach my $c (sort keys %{ $currentColorMap{$fgbg}{$type} }) {
        foreach my $i (sort keys %{ $currentColorMap{$fgbg}{$type}{$c} }) {
            if ($i eq '*'
                || !($currentColorMap{$fgbg}{$type}{$c}{$i} eq ($currentColorMap{$fgbg}{$type}{$c}{'*'} || '')
                     || !$currentColorMap{$fgbg}{$type}{$c}{$i})) {
                print COLORS "$c,$i,"
                  . ($currentColorMap{$fgbg}{$type}{$c}{$i}
                       ? $currentColorMap{$fgbg}{$type}{$c}{$i}
                       : 'default')
                  . "\n";
            }
        }
    }

    $type = 'zephyr-personal';
    print COLORS "MODE: $type\n";
    foreach my $s (sort keys %{ $currentColorMap{$fgbg}{$type} }) {
        print COLORS "$s,"
           . ($currentColorMap{$fgbg}{$type}{$s}
                ? $currentColorMap{$fgbg}{$type}{$s}
                : 'default')
           . "\n";
    }

    $type = 'aim';
    print COLORS "MODE: $type\n";
    foreach my $s (sort keys %{ $currentColorMap{$fgbg}{$type} }) {
        print COLORS "$s,"
          . ($currentColorMap{$fgbg}{$type}{$s}
               ? $currentColorMap{$fgbg}{$type}{$s}
               : 'default')
          . "\n";
    }

    $type = 'jabber';
    print COLORS "MODE: $type\n";
    foreach my $s (sort keys %{ $currentColorMap{$fgbg}{$type} }) {
        print COLORS "$s,"
          . ($currentColorMap{$fgbg}{$type}{$s}
               ? $currentColorMap{$fgbg}{$type}{$s}
               : 'default')
          . "\n";
    }

    $type = 'irc';
    print COLORS "MODE: $type\n";
    foreach my $srv (sort keys %{ $currentColorMap{$fgbg}{$type} }) {
        foreach my $chan (sort keys %{ $currentColorMap{$fgbg}{$type}{$srv} }) {
            print COLORS "$srv,$chan,"
              . ($currentColorMap{$fgbg}{$type}{$srv}{$chan}
                   ? $currentColorMap{$fgbg}{$type}{$srv}{$chan}
                   : 'default')
              . "\n";
        }
    }


    $type = 'loopback';
    print COLORS "MODE: $type\n";
    print COLORS ($currentColorMap{$fgbg}{$type}
                    ? $currentColorMap{$fgbg}{$type}
                    : 'default')
      . "\n";

    close(COLORS);
}

sub load($)
{
    my $fgbg = shift;
    return unless (grep(/^[fb]g$/, $fgbg));

    $currentColorMap{$fgbg} = {};
    $savedColorMap{$fgbg} = {};

    # Parse the color file.
    if ($fgbg eq 'bg') {
        open(COLORS, "<$config_dir/colormap_bg") || return;
    }
    else {
        open(COLORS, "<$config_dir/colormap") || return;
    }


    my $mode = "zephyr";

    foreach my $line (<COLORS>) {
        chomp($line);
        if ($line =~ /^MODE: (.*)$/) {
            if (lc($1) eq "zephyr") {
                $mode = 'zephyr';
            } elsif (lc($1) eq "zephyr-personal") {
                $mode = 'zephyr-personal';
            } elsif (lc($1) eq "aim") {
                $mode = 'aim';
            } elsif (lc($1) eq "jabber") {
                $mode = 'jabber';
            } elsif (lc($1) eq "irc") {
                $mode = 'irc';
            } elsif (lc($1) eq "loopback") {
                $mode = 'loopback';
            } else {
                $mode = 'zephyr';
            }
        } elsif ($mode eq 'zephyr' && $line =~ /^(.+),(.+),(b?)(black|red|green|yellow|blue|magenta|cyan|white|default|[0-9]{1,3})$/i) {
            $currentColorMap{$fgbg}{$mode}{lc($1)}{lc($2)} = lc($4);
            $savedColorMap{$fgbg}{$mode}{lc($1)}{lc($2)}   = lc($4);
        } elsif ($mode eq 'zephyr-personal' && $line =~ /^(.+),(b?)(black|red|green|yellow|blue|magenta|cyan|white|default|[0-9]{1,3})$/i) {
            $currentColorMap{$fgbg}{$mode}{lc($1)} = lc($3);
            $savedColorMap{$fgbg}{$mode}{lc($1)}   = lc($3);
        } elsif (($mode eq 'aim' || $mode eq 'jabber') && $line =~ /^(.+),(b?)(black|red|green|yellow|blue|magenta|cyan|white|default|[0-9]{1,3})$/i) {
            $currentColorMap{$fgbg}{$mode}{lc($1)} = lc($3);
            $savedColorMap{$fgbg}{$mode}{lc($1)}   = lc($3);
        } elsif (($mode eq 'irc') && $line =~ /^(.+),(.+),(b?)(black|red|green|yellow|blue|magenta|cyan|white|default|[0-9]{1,3})$/i) {
            $currentColorMap{$fgbg}{$mode}{lc($1)}{lc($2)} = lc($4);
            $savedColorMap{$fgbg}{$mode}{lc($1)}{lc($2)}   = lc($4);
        } elsif ($mode eq 'loopback' && $line =~ /^(b?)(black|red|green|yellow|blue|magenta|cyan|white|default|[0-9]{1,3})$/i) {
            $currentColorMap{$fgbg}{$mode} = lc($2);
            $savedColorMap{$fgbg}{$mode}   = lc($2);
        }
    }
    close(COLORS);
}
