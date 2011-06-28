package Naughty;
use Moose::Role;

has qty_limit => (is => "rw", isa => "Int", default => sub { 1 });
has extra_price_on_cancel => (is => "rw", isa => "Bool");

has __last_price => (is => "rw", isa => "CodeRef");

around cancel_order => sub {
    my ($next, $self, $id, $cb) = @_;
    if ($self->extra_price_on_cancel) {
        $self->__last_price->()
    }
    $self->$next($id, $cb);
};

around on_price => sub {
    my ($next, $self, $price, $qty, $meta) = @_;
    $self->__last_price(sub { $self->on_price($price, $qty, $meta) });
    $self->$next($price, $self->qty_limit, $meta);
};

1;
