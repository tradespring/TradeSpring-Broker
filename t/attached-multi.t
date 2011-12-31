#!/usr/bin/perl -w
use strict;
use Test::More;
use Test::Deep;
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
#        (traits => ['Stop', 'Timed', 'Update', 'Attached', 'OCA']);
        (traits => ['Stop', 'Timed', 'Attached', 'OCA']);

my $order = {};


sub mk_cb {
    my $log = shift;
    my $ready = shift;
    my @cb = qw(match summary cancel);
    push @cb, 'ready' if $ready;
    map { my $name = $_;
          ("on_$name" => sub { push @$log, [$name, @_] }) } @cb;
}

{
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1, type => 'lmt', price => 7000, qty => 1 },
                                          mk_cb($log, 1));
    diag $order_id;

    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    my $order_id2 = $broker->register_order( { dir => -1, type => 'lmt', price => 7010, qty => 1,
                                               attached_to => $order_id, oca_group => 1},
                                             mk_cb($log, 1));

    my $order_id3 = $broker->register_order( { dir => -1, type => 'stp', price => 6990, qty => 1,
                                               attached_to => $order_id, oca_group => 1},
                                             mk_cb($log, 1));

    my $order_id4 = $broker->register_order( { dir => -1, type => 'stp', qty => 1,
                                               trail => 10, effective => 7009,
                                               attached_to => $order_id, oca_group => 1},
                                             mk_cb($log, 1));

    $broker->on_price(7010);
    my $wait = AE::cv;
    my $w; $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['ready', $order_id2, 'submitted'],
                     ['ready', $order_id3, 'submitted'],
                     ['ready', $order_id4, 'submitted'],
                 ]);
    @$log = ();

    $broker->on_price(7000);
    is_deeply($log, [['match', 7000, 1],
                     ['summary', 1, 0]
                 ]);
    @$log = ();
    $broker->on_price(7001);
    $wait = AE::cv;
    $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    cmp_deeply(
        $log,
        bag(['ready', $order_id3, 'new'],
            ['ready', $order_id4, 'new'],
            ['ready', $order_id2, 'new']
        )
    );

    @$log = ();
    $broker->on_price(7009);
    $broker->on_price(7009);

    is_deeply($log, []);

    $broker->on_price(7004);


    is_deeply($log, []);

    $broker->on_price(6999);

    is_deeply($log, [['ready', $order_id4, 'new'],
                     ['match', 6999, 1],
                     ['summary', 1, 0],
                     ['summary', 0, 1],
                     ['summary', 0, 1],
                 ]);
    is(scalar keys %{$broker->local_orders}, 0);
}

done_testing;
