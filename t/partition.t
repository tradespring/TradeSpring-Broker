#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Partition;
use TradeSpring::Broker::Local;

my $b1 = TradeSpring::Broker::Local->new;
my $b2 = TradeSpring::Broker::Local->new;

my $broker = TradeSpring::Broker::Partition->new_with_traits
     (traits => ['Stop', 'Update', 'Attached', 'OCA'],
      backends => [ {
          broker => $b1,
          qtymap => 4,
          qtymax => 5,
      }, {
          broker => $b2,
          qtymap => 1,
      }]
  );

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
    my $order_id = $broker->register_order( { dir => 1, type => 'lmt', price => 7000, qty => 10 },
                                            mk_cb($log, 1));
    diag $order_id;

    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    my $order_id2 = $broker->register_order( { dir => -1, type => 'lmt', price => 7010, qty => 10,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1) );
#    diag "TP: $order_id2";

    my $order_id3 = $broker->register_order( { dir => -1, type => 'stp', price => 6990, qty => 10,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1));
#    diag "SL: $order_id3";
    $broker->on_price(7010);
    my $wait = AE::cv;
    my $w; $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['ready', $order_id2, 'submitted'],
                     ['ready', $order_id3, 'submitted']]);;

    @$log = ();

    $b1->on_price(7000);
    is_deeply($log, [['match', 7000, 8],
                 ]);

    $b2->on_price(7000);
    is_deeply($log, [['match', 7000, 8],
                     ['match', 7000, 2],
                     ['summary', 10, 0]
                 ]);

    @$log = ();
    $broker->on_price(7001);
    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id3, 'new'],
                     ['ready', $order_id2, 'new']]);

    @$log = ();
    $b1->on_price(7010, 1);
    $broker->cancel_order($order_id2,
                          sub { push @$log, ['cancel', @_] } );
    is_deeply($log, [['match', 7010, 4],
                     ['cancel', 'cancelled'],
                     ['summary', 4, 6],
                     ['summary', 0, 10]]);
}

done_testing;
