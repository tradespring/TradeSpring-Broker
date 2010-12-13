package TradeSpring::Broker::Role::Stop;
use Moose::Role;
use Method::Signatures::Simple;

requires 'on_price';

has stp_orders => (is => "rw", isa => "HashRef", default => sub { {} });

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;
    if ($order->{type} eq 'stp') {
        my $o =
        { order => $order,
          matched => 0,
          execute => sub { $_[0] * $order->{dir} >= $order->{price} * $order->{dir} },
          %args };

        return $self->stp_orders->{$order->{id}} = $o;
    }
    return $next->(@_);
};

around 'cancel_order' => sub {
    my $next = shift;
    my ($self, $id, $cb) = @_;
    if (my $o = delete $self->stp_orders->{$id}) {
        $o->{cancelled}++;
        $cb->('cancelled');
        return $o->{on_summary}->(0, $o->{order}{qty});
    }
    $next->(@_);
};

before 'on_price' => method ($price, $qty_limit, $time) {
    for (keys %{$self->stp_orders}) {
        my $o = $self->stp_orders->{$_};
        next if !$o || $o->{cancelled};
        unless ($o->{submitted}) {
            ++$o->{submitted};
            $o->{on_ready}->('new') if $o->{on_ready};
        }
        if ($o->{execute}->($price)) {
            $o->{cancelled}++;
            delete $self->stp_orders->{$_};
#            warn "==> submitting mkt  / $o->{order}{qty} / $o $o->{on_summary}";
            my $stplmt = delete $o->{order}{stplmt};
            my $new_o = { %{$o->{order}}, $stplmt ?
                                    (type => 'lmt', price => $stplmt)
                                  : (type => 'mkt', price => 0) };
            $self->orders->{$new_o->{id}} =
                $self->submit_order($new_o,
                                    on_ready => $o->{on_ready},
                                    on_error => $o->{on_error},
                                    on_match => $o->{on_match},
                                    on_summary => $o->{on_summary});
        }
    }
};

__PACKAGE__
