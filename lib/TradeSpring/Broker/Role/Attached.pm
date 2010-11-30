package TradeSpring::Broker::Role::Attached;
use Moose::Role;
use Method::Signatures::Simple;
use AnyEvent;

has attached => (is => "rw", isa => "HashRef", default => sub { {} } );

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;

    if (my $attached_to = $order->{attached_to}) {
        my $id = $order->{id};
#        warn "has attachement ($id depends on $attached_to";
        my $o = { order => $order,
                  %args };
        my $w; $w = AnyEvent->timer(after=>0.1, cb => sub {
                                        $args{on_ready}->('submitted'); undef $w })
            if $args{on_ready};

        push @{$self->attached->{$attached_to} ||= []}, $id;
        return $o;
    }
    else {
        my $o = $next->(@_);
        return $o if $o->{order}{_attached};

        my $summary = $o->{on_summary};
        my $id = $o->{order}{id};
        $o->{order}{_attached} = 1;
        $o->{on_summary} = sub {
            my ($filled, $cancelled) = @_;
            $summary->($filled, $cancelled);

            if ($filled) {
                my $ids = delete $self->attached->{$id} or return;
                for my $oid (@$ids) {
                    my $oo = $self->get_order($oid);
                    my $new_o = { %{delete $oo->{order}} };
                    delete $new_o->{attached_to};
                    $new_o->{qty} -= $cancelled;
                    $self->orders->{$oid} = $self->submit_order($new_o,
                                                                %{$oo} );
                }
            }
            else {
                while (my $oid = shift @{$self->attached->{$id}}) {
                    $self->cancel_order($oid, sub {
                                            # warn "cancelling from attach root"
                                        });
                }
                delete $self->attached->{$id};
            }
        };
        return $o;
    }
};

around 'cancel_order' => sub {
    my ($next, $self, $id, $cb) = @_;
    my $o = $self->get_order($id);
#    warn "==> cancelling";
    if (my $aid = $o->{order}{attached_to}) {
#        warn "==> cancelling $o $aid";
        if ($self->attached->{$aid}) {
            @{$self->attached->{$aid}} = grep { $_ ne $id } @{$self->attached->{$aid}};
        }
        $cb->('cancelled');
        $o->{cancelled}++;
        $o->{on_summary}->(0, $o->{order}{qty});
        return 1;
    }
    $self->$next($id, $cb);
};

__PACKAGE__
