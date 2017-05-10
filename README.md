# gpib
Simple perl GPIB interface with some instrument abstractions.

GPIBWrap merges the APIs of RPCINST, and VXI11::Client so the same test code can use either. Instrument abstractions
are built as needed with the needed features. Generic_Instrument.pm can be used to represent any instrument or as a template
for a new abstraction.
