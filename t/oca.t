#!/usr/bin/perl -w
use strict;
use Test::More;
use TradeSpring::Broker::Local;

my $broker = TradeSpring::Broker::Local->new_with_traits
     (traits => ['Stop', 'Update', 'Attached', 'OCA']);

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
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1) );
#    diag "TP: $order_id2";

    my $order_id3 = $broker->register_order( { dir => -1, type => 'stp', price => 6990, qty => 1,
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

    $broker->on_price(7000);
    is_deeply($log, [['match', 7000, 1],
                     ['summary', 1, 0]
                 ]);

    @$log = ();
    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id3, 'new'],
                     ['ready', $order_id2, 'new']]);
    @$log = ();
    $broker->on_price(6990);
    is_deeply($log, [['ready', $order_id3, 'new'],
                     ['match', 6990, 1],
                     ['summary', 1, 0],
                     ['summary', 0, 1]]);

    is(scalar keys %{$broker->local_orders}, 0);

    @$log = ();
    $broker->on_price(6990);
    is_deeply($log, []);
    $broker->on_price(7010);
    is_deeply($log, []);
}


# test for update
{
    my $log = [];
    my ($order_id, $order_id2, $order_id3) =
        register_bracket($broker, $log,
                         { dir => 1, type => 'lmt', price => 7000, qty => 1 },
                         { dir => -1, type => 'lmt', price => 7010, qty => 1 },
                         { dir => -1, type => 'stp', price => 6990, qty => 1 }
                     );

    $broker->on_price(7000);
    is_deeply($log, [['match', 7000, 1],
                     ['summary', 1, 0]
                 ]);


    @$log = ();
    $broker->on_price(7001);
    is_deeply($log, [['ready', $order_id3, 'new'],
                     ['ready', $order_id2, 'new']]);

    @$log = ();
    $broker->update_order( $order_id2, 7011, undef, sub {
                               push @$log, ['updating'];
                           });

    my $wait = AE::cv;

    $broker->on_price(7010);
    my $w; $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    is_deeply($log, [['updating'],
                     ['ready', $order_id2, 'new']]);

    @$log = ();
    $broker->on_price(6990);
    is_deeply($log, [['ready', $order_id3, 'new'],
                     ['match', 6990, 1],
                     ['summary', 1, 0],
                     ['summary', 0, 1]]);

    is(scalar keys %{$broker->local_orders}, 0);

    @$log = ();
    $broker->on_price(6990);
    is_deeply($log, []);
    $broker->on_price(7012);
    is_deeply($log, []);
}

# test for cancel
{
    my $log = [];
    my ($order_id, $order_id2, $order_id3) =
        register_bracket($broker, $log,
                         { dir => 1, type => 'lmt', price => 7000, qty => 1 },
                         { dir => -1, type => 'lmt', price => 7010, qty => 1 },
                         { dir => -1, type => 'stp', price => 6990, qty => 1 }
                     );
    $broker->cancel_order($order_id,
                          sub { push @$log, ['cancel', @_] } );

    is_deeply($log,
          [ [ 'cancel', 'cancelled'],
            [ 'summary', 0, 1],
            [ 'summary', 0, 1],
            [ 'summary', 0, 1] ]);

}

done_testing;

sub register_bracket {
    my ($broker, $log, $entry, $tp, $sl) = @_;
    my $order_id = $broker->register_order( $entry,
                                            mk_cb($log, 1));
    diag $order_id;

    $broker->on_price(7010);
    is_deeply($log, [['ready', $order_id, 'new']]);

    my $order_id2 = $broker->register_order( { %$tp,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1) );
#    diag "TP: $order_id2";

    my $order_id3 = $broker->register_order( { %$sl,
                                               attached_to => $order_id, oca_group => $order_id },
                                             mk_cb($log, 1) );
#    diag "SL: $order_id3";
    $broker->on_price(7010);
    my $wait = AE::cv;
    my $w; $w = AE::timer(0.5, 0, sub { undef $w; $wait->send });
    $wait->recv;

    is_deeply($log, [['ready', $order_id, 'new'],
                     ['ready', $order_id2, 'submitted'],
                     ['ready', $order_id3, 'submitted']]);;

    @$log = ();
    return ($order_id, $order_id2, $order_id3);
}
