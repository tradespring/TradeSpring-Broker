#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Local;
use Test::LeakTrace;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update', 'Attached', 'OCA']);
#my $broker = TradeSpring::Broker::Local->new;

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
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lmt',
                                              price => 7000,
                                              qty => 1 },
                                          mk_cb($log, 1));
    $broker->cancel_order($order_id,
                          sub { push @$log, ['cancel', @_] } );
};


use AnyEvent;
no_leaks_ok {
    my $cv = AE::cv;
    my $log = [];
    my $order = $broker->submit_order( { id => 'xxx',
                                         dir => 1,
                                         type => 'lmt',
                                         price => 7000,
                                         qty => 1 },
                                       mk_cb($log, 1));
    $broker->cancel_order('xxx',
                          sub { push @$log, ['cancel', @_] } );

    my $w; $w = AnyEvent->timer(after => 1, cb => sub { $cv->send });
    $cv->recv;

};

no_leaks_ok {
    my $cv = AE::cv;
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1,
                                              type => 'lmt',
                                              price => 7000,
                                              qty => 1 },
                                            mk_cb($log, 1));
    $broker->cancel_order($order_id,
                          sub { push @$log, ['cancel', @_] } );

    my $w; $w = AnyEvent->timer(after => 1, cb => sub { $cv->send });
    $cv->recv;

};


no_leaks_ok {
    my $cv = AE::cv;
    my $log = [];
    my $order_id = $broker->register_order( 1, 'lmt', 7000, 1,
                                          mk_cb($log, 1));
    $broker->on_price(7010);
    $broker->on_price(7000);
    $broker->filled_orders({});

    my $w; $w = AnyEvent->timer(after => 1, cb => sub { $cv->send });
    $cv->recv;
};

no_leaks_ok {
    my $log = [];
    my $order_id = $broker->register_order( { dir => 1, type => 'lmt', price => 7000, qty => 1 },
                                            mk_cb($log, 1));
    diag $order_id;

    $broker->on_price(7010);

    my $order_id2 = $broker->register_order( { dir => -1, type => 'lmt', price => 7010, qty => 1,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1) );

    my $order_id3 = $broker->register_order( { dir => -1, type => 'stp', price => 6990, qty => 1,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1));


    $broker->on_price(7010);
    my $wait = AE::cv;
    my $w; $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    $broker->on_price(7000);
    $broker->on_price(7001);
    $broker->on_price(6990);
    $broker->on_price(6990);
    $broker->on_price(7010);

    $broker->filled_orders({});
};


done_testing;

