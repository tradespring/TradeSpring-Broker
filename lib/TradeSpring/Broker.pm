package TradeSpring::Broker;
use 5.10.1;
use Moose;
use Hash::Util::FieldHash qw(id);
use Method::Signatures::Simple;
use List::Util qw(min);

with 'MooseX::Traits';

has '+_trait_namespace' => (default => 'TradeSpring::Broker::Role');

has orders => (is => "rw", isa => "HashRef", default => sub { {} });
has filled_orders => (is => "rw", isa => "HashRef", default => sub { {} });
has delayed => (is => "rw", isa => "ArrayRef", default => sub { [] });
has hit_probability => (is => "rw", isa => "Int", default => sub { 1 });

method register_order {
    my $order = shift;
    my %callbacks;
    if (!ref($order)) {
        my $dir = $order;
        (my ($type, $price, $qty), %callbacks) = @_;
        $order = { dir => $dir,
                   type => $type,
                   price => $price,
                   qty => $qty,
               };
    }
    else {
        %callbacks = @_;
    }

    my $id = $order->{id} = 'b'.id($order);
    my $on_ready = delete $callbacks{on_ready};
    my $on_summary = delete $callbacks{on_summary};
    $self->orders->{$id} = $self->submit_order($order, %callbacks,
                                               $on_summary ?
                                                   (on_summary => sub {
                                                        my $o = $self->orders->{$id};
                                                        if ($o->{matched}) {
                                                            my $order = $o->{order};
                                                            $order->{qty} = $o->{matched};
                                                            $order->{price} = $o->{price_sum} / $o->{matched};
                                                            $order->{fill_time} = $o->{last_fill_time};
                                                            $self->filled_orders->{$id} = $order;
                                                        }
                                                        $on_summary->(@_);
                                                        undef $on_ready;
                                                        undef $on_summary;
                                                        delete $self->orders->{$id};
                                                    }) : (),
                                               $on_ready ?
                                                   (on_ready => sub { $on_ready->($id, @_) }) : ()
                                               );
    unless ($self->orders->{$id}{order}{id}) {
        warn " obscure order: ".Dumper($self->orders->{$id});use Data::Dumper;
    }
    return $id;
}

method get_order ($id) {
    return $self->orders->{$id};
}

method get_orders($cb) {
    for (keys %{$self->filled_orders}) {
        $cb->('filled', $_, $self->filled_orders->{$_}); # XXX
    }
    for (sort { ($self->orders->{$a}->{order}{attached_to} || 0) <=> ($self->orders->{$b}->{order}{attached_to} || 0) }
             keys %{$self->orders}) {
        $cb->('new', $_, $self->orders->{$_}{order}); # XXX: status
    }
}

method unregister_order ($id, $cb) {
    my $o = $self->get_order($id);
    $self->cancel_order($o, sub {
                            if ($_[0] eq 'cancelled') {
                                delete $self->orders->{$id};
                            }
                            $cb->(@_);
                        });
}

method fill_order ($o, $price, $qty, $meta) {
    $o->{matched} += $qty;
    $o->{price_sum} ||= 0;
    $o->{price_sum} += $price * $qty;
    $o->{on_match}->($price, $qty);
    $o->{last_fill_time} = $meta->{timestamp};
    if ($o->{matched} == $o->{order}{qty}) {
        $o->{on_summary}->($o->{matched}, 0);
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;


