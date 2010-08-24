package TradeSpring::Broker::Role::OCA;
use Moose::Role;
use Method::Signatures::Simple;

has oca_groups => (is => "rw", isa => "HashRef", default => sub { {} } );

around 'submit_order' => sub {
    my $next = shift;
    my ($self, $order, %args) = @_;

    my $oca_group = $order->{oca_group};

    my $o = $next->(@_);
    return $o unless $oca_group;

    my $id = $o->{order}{id};
    return $o if $o->{order}{_oca};

    $o->{order}{_oca} = 1;
    push @{$self->oca_groups->{$oca_group} ||= []} , $id;


    my $summary = $o->{on_summary};
    $o->{on_summary} = sub {
        my ($filled, $cancelled) = @_;
#        warn "wrapped summary of oca($id): $filled $cancelled";
        my $ids = delete $self->oca_groups->{$oca_group};
        $summary->($filled, $cancelled);
        for my $oid (@$ids) {
#            warn "==> $oid (from $id)";
            $self->cancel_order($oid, sub {
#                                    warn "oca cancelling $oid";
                                })
                unless $id eq $oid;
        }
    };
#    warn "==> munging oca summary $id /  $o->{on_summary}" ;

    return $o;
};


__PACKAGE__
