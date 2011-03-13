package TradeSpring::Broker::Role::Timed;
use Moose::Role;
use Method::Signatures::Simple;
use AnyEvent;
use Scalar::Util qw(looks_like_number);

has timed_orders => (is => "rw", isa => "HashRef", default => sub { {} } );

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;

    if (my $timed = $order->{timed}) {
        unless (looks_like_number $timed) {
            warn "incorrect time format: $timed";
            return $next->(@_);
        }
        my $o =
        { order => $order,
          matched => 0,
          %args };

        return $self->timed_orders->{$order->{id}} = $o;
    }
    return $next->(@_);
};

around 'cancel_order' => sub {
    my $next = shift;
    my ($self, $id, $cb) = @_;
    if (my $o = delete $self->timed_orders->{$id}) {
        $o->{cancelled}++;
        return $o->{on_summary}->(0, $o->{order}{qty});
    }
    $next->(@_);
};

before 'on_price' => method ($price, $qty_limit, $meta) {
    for (keys %{$self->timed_orders}) {
        my $o = $self->timed_orders->{$_};
        next if !$o || $o->{cancelled};
        unless ($o->{submitted}) {
            ++$o->{submitted};
            $o->{on_ready}->('new') if $o->{on_ready};
        }
        unless (ref $meta) {
            warn "incorrect meta format for time: $meta";
        }
        if ($meta->{timestamp} >= $o->{order}{timed}) {
            $o->{cancelled}++;
            delete $self->timed_orders->{$_};
            delete $o->{order}{timed};
            my $new_o = { %{$o->{order}} };
            $self->orders->{$new_o->{id}} =
                $self->submit_order($new_o,
                                    on_ready => $o->{on_ready},
                                    on_error => $o->{on_error},
                                    on_match => $o->{on_match}, on_summary => $o->{on_summary});
        }
    }
};

__PACKAGE__
