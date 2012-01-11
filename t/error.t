#!/usr/bin/perl -w
use strict;
use Test::More;
use lib 't/lib';
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update', '+OrderError']);

sub mk_cb {
    my $log = shift;
    my $ready = shift;
    my @cb = qw(match summary error cancel);
    push @cb, 'ready' if $ready;
    map { my $name = $_;
          ("on_$name" => sub { push @$log, [$name, @_] }) } @cb;
}
{
    my $log = [];
    my $order_id = $broker->register_order({ dir => 1,
                                             type => 'stp',
                                             price => 7000,
                                             qty => 2 },
                                           mk_cb($log, 1));
    diag $order_id;
    $broker->on_price(6999);
    is_deeply($log, [['ready', $order_id, 'new']]);
    @$log = ();
    $broker->on_price(7000, 1);


    my $cv = AE::cv;
    my $w; $w = AnyEvent->timer(after => 1, cb => sub { $cv->send(1); undef $w});
    $cv->recv;
    is_deeply($log, [['ready', $order_id, 'new'],
                     ['error', 'Fail', 'hate software'],
                     ['summary', 0, 2]]);
    warn Dumper($log) ;use Data::Dumper;

    @$log = ();
}


done_testing;
