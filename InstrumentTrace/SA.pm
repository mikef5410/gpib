# -*- mode: perl -*-
package InstrumentTrace::SA;
use Moose;
use PDL::Core;
use namespace::autoclean;

with('Throwable');    #Use Try::Tiny to catch my errors
with('MooseX::Log::Log4perl');

has 'FA' => ( is => 'rw', isa => 'Num', default => undef );    #Start Freq
has 'FB' => ( is => 'rw', isa => 'Num', default => undef );    #Stop Freq
has 'RL' => ( is => 'rw', isa => 'Num', default => undef );    #Ref Level
has 'RB' => ( is => 'rw', isa => 'Num', default => undef );    #Res BW
has 'VB' => ( is => 'rw', isa => 'Num', default => undef );    #Vid BW
has 'ST' => ( is => 'rw', isa => 'Num', default => undef );    #Sweep time
has 'LG' => ( is => 'rw', isa => 'Num', default => undef );    #dB/div
has 'AUNITS' => ( is => 'rw', default => undef );                                #Power units
has 'TDATA' => ( is => 'rw', isa => 'PDL', default => sub { PDL->null(); } );    #Trace data
has 'TSIZE' => ( is => 'rw', isa => 'Int', default => undef );                   #Num points

__PACKAGE__->meta->make_immutable;
1;
