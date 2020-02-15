use 5.014;
use strict;
use warnings;
use B ();
use Carp ();
use Import::Into ();
use MooX::Press 0.048 ();
use MooX::Press::Keywords ();
use Syntax::Keyword::Try ();
use feature ();

package Zydeco;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.500';

use Keyword::Simple ();
use PPR;
use B::Hooks::EndOfScope;
use Exporter::Shiny our @EXPORT = qw( version authority overload );
use Devel::StrictMode qw(STRICT);

BEGIN {
	package Zydeco::_Gather;
	my %gather;
	my %stack;
	sub import {
		my ($me, $action, $caller) = (shift, shift, scalar caller);
		if ($action eq -gather) {
			while (@_) {
				my ($k, $v) = splice @_, 0, 2;
				if (my ($kind,$pkg) = ($k =~ /^(class|role|class_generator|role_generator):(.+)$/)) {
					if ( my @stack = @{ $stack{$me}{$caller}||[] } ) {
						pop @stack if $stack[-1] eq $pkg;
						if (@stack) {
							$v->{_stack} = \@stack;
							$kind = '_defer_'.$kind;
						}
					}
					push @{ $gather{$me}{$caller}{$kind}||=[] }, $pkg, $v;
				}
				else {
					$gather{$me}{$caller}{$k} = $v;
				}
			}
		}
		elsif ($action eq -go) {
			if ($gather{$me}{$caller}{'_defer_role'}) {
				require Carp;
				Carp::croak('Nested roles are not supported');
			}
			if ($gather{$me}{$caller}{'_defer_role_generator'}) {
				require Carp;
				Carp::croak('Nested role generators are not supported');
			}
			if ($gather{$me}{$caller}{'_defer_class_generator'}) {
				$me->_undefer_class_generators($gather{$me}{$caller}{'class_generator'}||=[], delete $gather{$me}{$caller}{'_defer_class_generator'});
			}
			if ($gather{$me}{$caller}{'_defer_class'}) {
				$me->_undefer_classes($gather{$me}{$caller}{'class'}, delete $gather{$me}{$caller}{'_defer_class'});
			}
			
			if ($gather{$me}{$caller}{debug}) {
				require Data::Dumper;
				warn Data::Dumper::Dumper($gather{$me}{$caller});
			}
			
			@_ = ('MooX::Press' => $gather{$me}{$caller});
			goto \&MooX::Press::import;
		}
		elsif ($action eq -parent) {
			push @{ $stack{$me}{$caller}||=[] }, $_[0];
		}
		elsif ($action eq -unparent) {
			pop @{ $stack{$me}{$caller} };
		}
		else {
			die;
		}
	}
	sub _undefer_classes {
		my ($me, $classes, $d) = @_;
		my %class_hash = @{$classes||[]};
		my @deferred;
		my $max_depth = 0;
		while (@$d) {
			my ($class, $spec) = splice(@$d, 0, 2);
			$spec->{_class_name} = $class;
			$spec->{_depth}      = @{ $spec->{_stack} };
			push @deferred, $spec;
			$max_depth = $spec->{_depth} if $spec->{_depth} > $max_depth;
		}
		DEPTH: for my $depth (1 .. $max_depth) {
			SPEC: for my $spec (@deferred) {
				next SPEC unless $spec->{_depth} == $depth;
				my $parent_key = join('|', @{$spec->{_stack}});
				my $my_key     = join('|', @{$spec->{_stack}}, $spec->{_class_name});
				if (not $class_hash{$parent_key}) {
					require Carp;
					Carp::croak(sprintf(
						'%s is nested in %s but %s is not a class',
						$spec->{_class_name},
						$spec->{_stack}[-1],
						$spec->{_stack}[-1],
					));
				}
				push @{ $class_hash{$parent_key}{subclass} ||=[] }, $spec->{_class_name}, $spec;
				$class_hash{$my_key} = $spec;
			}
		}
		for my $spec (@deferred) {
			delete $spec->{_stack};
			delete $spec->{_class_name};
			delete $spec->{_depth};
		}
	}
	sub _undefer_class_generators {
		my ($me, $classes, $d) = @_;
		while (@$d) {
			my ($class, $spec) = splice(@$d, 0, 2);
			my $extends = $spec->{_stack}[-1];
			my $next = delete($spec->{code});
			$spec->{code} = sub {
				my $got = $next->(@_);
				$got->{extends} ||= [$extends];
				$got;
			};
			delete $spec->{_stack};
			push @$classes, $class, $spec;
		}
	}

	$INC{'Zydeco/_Gather.pm'} = __FILE__;
};

#
# GRAMMAR
#

our $GRAMMAR = qr{
	(?(DEFINE)
	
		(?<PerlKeyword>
		
			(?: include         (?&MxpIncludeSyntax)   )|
			(?: class           (?&MxpClassSyntax)     )|
			(?: abstract        (?&MxpAbstractSyntax)  )|
			(?: role            (?&MxpRoleSyntax)      )|
			(?: interface       (?&MxpRoleSyntax)      )|
			(?: toolkit         (?&MxpToolkitSyntax)   )|
			(?: begin           (?&MxpHookSyntax)      )|
			(?: end             (?&MxpHookSyntax)      )|
			(?: type_name       (?&MxpTypeNameSyntax)  )|
			(?: extends         (?&MxpExtendsSyntax)   )|
			(?: with            (?&MxpWithSyntax)      )|
			(?: requires        (?&MxpWithSyntax)      )|
			(?: has             (?&MxpHasSyntax)       )|
			(?: constant        (?&MxpConstantSyntax)  )|
			(?: coerce          (?&MxpCoerceSyntax)    )|
			(?: method          (?&MxpMethodSyntax)    )|
			(?: factory         (?&MxpFactorySyntax)   )|
			(?: factory         (?&MxpFactoryViaSyntax))|
			(?: before          (?&MxpModifierSyntax)  )|
			(?: after           (?&MxpModifierSyntax)  )|
			(?: around          (?&MxpModifierSyntax)  )|
			(?: multi           (?&MxpMultiSyntax)     )|
			(?: try             (?&TrySyntax)          )
		)#</PerlKeyword>
		
		(?<MxpSimpleIdentifier>
		
			(?&PerlIdentifier)|(?&PerlBlock)
		)#</MxpSimpleIdentifier>
		
		(?<MxpSimpleIdentifiers>
		
			(?&MxpSimpleIdentifier)
			(?:
				(?&PerlOWS)
				,
				(?&PerlOWS)
				(?&MxpSimpleIdentifier)
			)*
		)#</MxpSimpleIdentifiers>
		
		(?<MxpDecoratedIdentifier>
			
			(?: \+ )?                                     # CAPTURE:plus
			(?: \* | \$ )?                                # CAPTURE:asterisk
			(?: (?&MxpSimpleIdentifier) )                 # CAPTURE:name
			(?: \! | \? )?                                # CAPTURE:postfix
		)#</MxpDecoratedIdentifier>
		
		(?<MxpDecoratedIdentifierSolo>
			(?: (?&MxpDecoratedIdentifier) )   # deliberately non-capturing
		)#</MxpDecoratedIdentifierSolo>
		
		(?<MxpDecoratedIdentifiers>
		
			(?&MxpDecoratedIdentifier)
			(?:
				(?&PerlOWS)
				,
				(?&PerlOWS)
				(?&MxpDecoratedIdentifier)
			)*
		)#</MxpDecoratedIdentifiers>
		
		(?<MxpSimpleTypeSpec>
		
			~?(?&PerlBareword)(?&PerlAnonymousArray)?
		)#</MxpSimpleTypeSpec>
		
		(?<MxpTypeSpec>
		
			(?&MxpSimpleTypeSpec)
			(?:
				\s*\&\s*
				(?&MxpSimpleTypeSpec)
			)*
			(?:
				\s*\|\s*
				(?&MxpSimpleTypeSpec)
				(?:
					\s*\&\s*
					(?&MxpSimpleTypeSpec)
				)*
			)*
		)#</MxpTypeSpec>
		
		(?<MxpExtendedTypeSpec>
		
			(?&MxpTypeSpec)|(?&PerlBlock)
		)#</MxpExtendedTypeSpec>
		
		(?<MxpSignatureElement>
		
			(?&PerlOWS)
			(?: (?&MxpExtendedTypeSpec))?                 # CAPTURE:type
			(?&PerlOWS)
			(?:                                           # CAPTURE:name
				(?&PerlVariable) | (\*(?&PerlIdentifier))
			)
			(?:                                           # CAPTURE:postamble
				\? | ((?&PerlOWS)=(?&PerlOWS)(?&PerlTerm))
			)?
		)#</MxpSignatureElement>
		
		(?<MxpSignatureList>
			
			(?&MxpSignatureElement)
			(?:
				(?&PerlOWS)
				,
				(?&PerlOWS)
				(?&MxpSignatureElement)
			)*
		)#</MxpSignatureList>
		
		(?<MxpAttribute>
		
			:
			[^\W0-9]\w*
			(?:
				[(]
					[^\)]+
				[)]
			)?
		)#</MxpAttribute>
		
		(?<MxpRoleList>
		
			(?&PerlOWS)
			(?:
				(?&PerlBlock) | (?&PerlQualifiedIdentifier)
			)
			(?:
				(?:\s*\?) | (?: (?&PerlOWS)(?&PerlList))
			)?
			(?:
				(?&PerlOWS)
				,
				(?&PerlOWS)
				(?:
					(?&PerlBlock) | (?&PerlQualifiedIdentifier)
				)
				(?:
					(?:\s*\?) | (?: (?&PerlOWS)(?&PerlList))
				)?
			)*
		)#</MxpRoleList>
		
		(?<MxpClassSyntax>
		
			(?&PerlOWS)
			(?: [+] )?                                    # CAPTURE:plus
			(?: (?&PerlQualifiedIdentifier) )?            # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )?                          # CAPTURE:block
			(?&PerlOWS)
		)#</MxpClassSyntax>
		
		(?<MxpIncludeSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlQualifiedIdentifier) )?            # CAPTURE:name
			(?&PerlOWS)
		)#</MxpIncludeSyntax>
		
		(?<MxpAbstractSyntax>
			
			(?&PerlOWS)
			class
			(?&PerlOWS)
			(?: [+] )?                                    # CAPTURE:plus
			(?: (?&PerlQualifiedIdentifier) )?            # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )?                          # CAPTURE:block
			(?&PerlOWS)
		)#</MxpAbstractSyntax>
		
		(?<MxpRoleSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlQualifiedIdentifier) )?            # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )?                          # CAPTURE:block
			(?&PerlOWS)
		)#</MxpRoleSyntax>
		
		(?<MxpHookSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:hook
			(?&PerlOWS)
		)#</MxpHookSyntax>
		
		(?<MxpTypeNameSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlIdentifier) )                      # CAPTURE:name
			(?&PerlOWS)
		)#</MxpTypeNameSyntax>
		
		(?<MxpToolkitSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlIdentifier) )                      # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:imports
						(?: (?&PerlQualifiedIdentifier)|(?&PerlComma)|(?&PerlOWS) )*
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
		)#</MxpToolkitSyntax>
		
		(?<MxpExtendsSyntax>
		
			(?&PerlOWS)
			(?:                                           # CAPTURE:list
				(?&MxpRoleList)
			)
			(?&PerlOWS)
		)#</MxpExtendsSyntax>
		
		(?<MxpWithSyntax>
		
			(?&PerlOWS)
			(?:                                           # CAPTURE:list
				(?&MxpRoleList)
			)
			(?&PerlOWS)
		)#</MxpWithSyntax>
		
		(?<MxpRequiresSyntax>
		
			(?&PerlOWS)
			(?: (?&MxpSimpleIdentifier) )                 # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
		)#</MxpRequiresSyntax>
		
		(?<MxpHasSyntax>
		
			(?&PerlOWS)
			(?: (?&MxpDecoratedIdentifiers) )             # CAPTURE:name
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?: (?&PerlList) )                      # CAPTURE:spec
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?:
				[=]
				(?&PerlOWS)
				(?: (?&PerlAssignment) )                   # CAPTURE:default
			)?
			(?&PerlOWS)
		)#</MxpHasSyntax>
		
		(?<MxpConstantSyntax>
		
			(?&PerlOWS)
			(?: (?&PerlIdentifier) )                      # CAPTURE:name
			(?&PerlOWS)
			=
			(?&PerlOWS)
			(?: (?&PerlExpression) )                      # CAPTURE:expr
			(?&PerlOWS)
		)#</MxpConstantSyntax>
		
		(?<MxpMethodSyntax>
		
			(?&PerlOWS)
			(?: \$? (?&MxpSimpleIdentifier) )?            # CAPTURE:name
			(?&PerlOWS)
			(?: ( (?&MxpAttribute) (?&PerlOWS) )+ )?      # CAPTURE:attributes
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:code
			(?&PerlOWS)
		)#</MxpMethodSyntax>
		
		(?<MxpMultiSyntax>
		
			(?&PerlOWS)
			method
			(?&PerlOWS)
			(?: (?&MxpSimpleIdentifier) )                 # CAPTURE:name
			(?&PerlOWS)
			(?: ( (?&MxpAttribute) (?&PerlOWS) )+ )?      # CAPTURE:attributes
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:code
			(?&PerlOWS)
		)#</MxpMultiSyntax>
		
		(?<MxpModifierSyntax>
		
			(?&PerlOWS)
			(?: (?&MxpSimpleIdentifiers) )                # CAPTURE:name
			(?&PerlOWS)
			(?: ( (?&MxpAttribute) (?&PerlOWS) )+ )?      # CAPTURE:attributes
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:code
			(?&PerlOWS)
		)#</MxpModifierSyntax>
		
		# Easier to provide two separate patterns for `factory`
		
		(?<MxpFactorySyntax>
		
			(?&PerlOWS)
			(?: (?&MxpSimpleIdentifier) )                 # CAPTURE:name
			(?&PerlOWS)
			(?: ( (?&MxpAttribute) (?&PerlOWS) )+ )?      # CAPTURE:attributes
			(?&PerlOWS)
			(?:
				[(]
					(?&PerlOWS)
					(?:                                     # CAPTURE:sig
						(?&MxpSignatureList)?
					)
					(?&PerlOWS)
				[)]
			)?
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:code
			(?&PerlOWS)
		)#</MxpFactorySyntax>
		
		(?<MxpFactoryViaSyntax>
		
			(?&PerlOWS)
			(?: (?&MxpSimpleIdentifier) )                 # CAPTURE:name
			(?&PerlOWS)
			(?:
				(: via )
				(?:                                        # CAPTURE:via
					(?&PerlBlock)|(?&PerlIdentifier)|(?&PerlString)
				)
			)?
			(?&PerlOWS)
		)#</MxpFactoryViaSyntax>
		
		(?<MxpCoerceSyntax>
		
			(?&PerlOWS)
			(?: from )?
			(?&PerlOWS)
			(?:                                           # CAPTURE:from
				(?&MxpExtendedTypeSpec)
			)
			(?&PerlOWS)
			(?: via )
			(?&PerlOWS)
			(?:                                           # CAPTURE:via
				(?&PerlBlock)|(?&PerlIdentifier)|(?&PerlString)
			)
			(?&PerlOWS)
			(?: (?&PerlBlock) )                           # CAPTURE:code
			(?&PerlOWS)
		)#</MxpCoerceSyntax>
		
		# try/catch/finally is implemented by another module
		# but we need to be able to grok it to be able to parse
		# blocks
		#
		(?<TrySyntax>
		
			(?&PerlOWS)
			(?: do )?
			(?&PerlOWS)
			(?&PerlBlock)
			(?:
				(?&PerlOWS)
				catch
				(?&PerlOWS)
				(?&PerlBlock)
			)?
			(?:
				(?&PerlOWS)
				finally
				(?&PerlOWS)
				(?&PerlBlock)
			)?
			(?&PerlOWS)
		)#</TrySyntax>
		
	)
	$PPR::GRAMMAR
}xso;

my %_fetch_re_cache;
sub _fetch_re {
	my $key = "@_";
	my $name = shift;
	my %opts = @_;
	
	$opts{anchor} ||= '';
	
	$_fetch_re_cache{$key} ||= do {
		"$GRAMMAR" =~ m{<$name>(.+)</$name>}s or die "could not fetch re for $name";
		(my $re = $1) =~ s/\)\#$//;
		my @lines = split /\n/, $re;
		for (@lines) {
			if (my ($named_capture) = /# CAPTURE:(\w+)/) {
				s/\(\?\:/\(\?<$named_capture>/;
			}
		}
		$re = join "\n", @lines;
		$opts{anchor} eq 'start' ? qr/ ^ $re $GRAMMAR   /xs :
		$opts{anchor} eq 'end'   ? qr/   $re $GRAMMAR $ /xs :
		$opts{anchor} eq 'both'  ? qr/ ^ $re $GRAMMAR $ /xs : qr/ $re $GRAMMAR /xs
	}
}

#
# HELPERS
#

sub _handle_signature_list {
	my $me = shift;
	my $sig = $_[0];
	my $seen_named = 0;
	my $seen_pos   = 0;
	my @parsed;
	
	return (
		0,
		'',
		'[]',
		'',
	) if !$sig;
	
	while ($sig) {
		$sig =~ s/^\s+//xs;
		last if !$sig;
		
		push @parsed, {};
		
		if ($sig =~ /^((?&PerlBlock)) $GRAMMAR/xso) {
			my $type = $1;
			$parsed[-1]{type}          = $type;
			$parsed[-1]{type_is_block} = 1;
			$sig =~ s/^\Q$type//xs;
			$sig =~ s/^((?&PerlOWS)) $GRAMMAR//xso;
		}
		elsif ($sig =~ /^((?&MxpTypeSpec)) $GRAMMAR/xso) {
			my $type = $1;
			$parsed[-1]{type}          = $type;
			$parsed[-1]{type_is_block} = 0;
			$sig =~ s/^\Q$type//xs;
			$sig =~ s/^((?&PerlOWS)) $GRAMMAR//xso;
		}
		else {
			$parsed[-1]{type} = 'Any';
			$parsed[-1]{type_is_block} = 0;
		}
		
		if ($sig =~ /^\*((?&PerlIdentifier)) $GRAMMAR/xso) {
			my $name = $1;
			$parsed[-1]{name}       = $name;
			$parsed[-1]{named}      = 1;
			$parsed[-1]{positional} = 0;
			++$seen_named;
			$sig =~ s/^\*\Q$name//xs;
			$sig =~ s/^((?&PerlOWS)) $GRAMMAR//xso;
		}
		elsif ($sig =~ /^((?&PerlVariable)) $GRAMMAR/xso) {
			my $name = $1;
			$parsed[-1]{name}       = $name;
			$parsed[-1]{named}      = 0;
			$parsed[-1]{positional} = 1;
			++$seen_pos;
			$sig =~ s/^\Q$name//xs;
			$sig =~ s/^((?&PerlOWS)) $GRAMMAR//xs;
		}
		
		if ($sig =~ /^\?/) {
			$parsed[-1]{optional} = 1;
			$sig =~ s/^\?((?&PerlOWS)) $GRAMMAR//xso;
		}
		elsif ($sig =~ /^=((?&PerlOWS))((?&PerlTerm)) $GRAMMAR/xso) {
			my ($ws, $default) = ($1, $2);
			$parsed[-1]{default} = $default;
			$sig =~ s/^=\Q$ws$default//xs;
			$sig =~ s/^((?&PerlOWS)) $GRAMMAR//xso;
		}
		
		if ($sig) {
			$sig =~ /^,/ or die "WEIRD SIGNATURE??? $sig";
			$sig =~ s/^,//;
		}
	}
	
	my @signature_var_list;
	my $type_params_stuff = '[';
	
	my (@head, @tail);
	if ($seen_named and $seen_pos) {
		while (@parsed and $parsed[0]{positional}) {
			push @head, shift @parsed;
		}
		while (@parsed and $parsed[-1]{positional}) {
			unshift @tail, pop @parsed;
		}
		if (grep $_->{positional}, @parsed) {
			require Carp;
			Carp::croak("Signature contains an unexpected mixture of positional and named parameters");
		}
		for my $p (@head, @tail) {
			my $is_optional = $p->{optional};
			$is_optional ||= ($p->{type} =~ /^Optional/s);
			if ($is_optional) {
				require Carp;
				Carp::croak("Cannot have optional positional parameter $p->{name} in signature with named parameters");
			}
			elsif ($p->{default}) {
				require Carp;
				Carp::croak("Cannot have positional parameter $p->{name} with default in signature with named parameters");
			}
			elsif ($p->{name} =~ /^[\@\%]/) {
				require Carp;
				Carp::croak("Cannot have slurpy parameter $p->{name} in signature with named parameters");
			}
		}
	}
	
	require B;

	my $extra = '';
	my $count = @parsed;
	while (my $p = shift @parsed) {
		$type_params_stuff .= B::perlstring($p->{name}) . ',' if $seen_named;
		if ($p->{name} =~ /^[\@\%]/) {
			die "Cannot have slurpy in non-final position" if @parsed;
			$extra .= sprintf(
				'my (%s) = (@_==%d ? %s{$_[-1]} : ());',
				$p->{name},
				$count,
				substr($p->{name}, 0, 1),
			);
			$p->{slurpy} = 1;
			if ($p->{type} eq 'Any') {
				$p->{type} = substr($p->{name}, 0, 1) eq '%' ? 'HashRef' : 'ArrayRef';
			}
		}
		else {
			push @signature_var_list, $p->{name};
		}
		
		if ($p->{type_is_block}) {
			$type_params_stuff .= sprintf('scalar(do %s)', $p->{type}) . ',';
		}
		else {
			$type_params_stuff .= B::perlstring($p->{type}) . ',';
		}
		if (exists $p->{optional} or exists $p->{default} or $p->{slurpy}) {
			$type_params_stuff .= '{';
			$type_params_stuff .= sprintf('optional=>%d,', !!$p->{optional}) if exists $p->{optional};
			$type_params_stuff .= sprintf('default=>sub{scalar(%s)},', $p->{default}) if exists $p->{default};
			$type_params_stuff .= sprintf('slurpy=>%d,', !!$p->{slurpy}) if exists $p->{slurpy};
			$type_params_stuff .= '},';
		}
	}
	
	@signature_var_list = '$arg' if $seen_named;
	$type_params_stuff .= ']';
	
	if (@head or @tail) {
		require Type::Params;
		'Type::Params'->VERSION(1.009002);
		my $head_stuff = join(q[,] => map { $_->{type_is_block} ? sprintf('scalar(do %s)', $_->{type}) : B::perlstring($_->{type}) } @head);
		my $tail_stuff = join(q[,] => map { $_->{type_is_block} ? sprintf('scalar(do %s)', $_->{type}) : B::perlstring($_->{type}) } @tail);
		my $opts = sprintf('{head=>%s,tail=>%s},', $head_stuff?"[$head_stuff]":0, $tail_stuff?"[$tail_stuff]":0);
		substr($type_params_stuff, 1, 0) = $opts; # insert options after "["
		unshift @signature_var_list, map $_->{name}, @head;
		push @signature_var_list, map $_->{name}, @tail;
	}
	
	return (
		$seen_named,
		join(',', @signature_var_list),
		$type_params_stuff,
		$extra,
	);
}

sub _handle_role_list {
	my $me = shift;
	my ($rolelist, $kind) = @_;
	my @return;
	
	while (length $rolelist) {
		$rolelist =~ s/^\s+//xs;
		
		my $prefix = '';
		my $role = undef;
		my $role_is_block = 0;
		my $suffix = '';
		my $role_params   = undef;
		
		if ($rolelist =~ /^((?&PerlBlock)) $GRAMMAR/xso) {
			$role = $1;
			$role_is_block = 1;
			$rolelist =~ s/^\Q$role//xs;
			$rolelist =~ s/^\s+//xs;
		}
		elsif ($rolelist =~ /^((?&PerlQualifiedIdentifier)) $GRAMMAR/xso) {
			$role = $1;
			$rolelist =~ s/^\Q$role//xs;
			$rolelist =~ s/^\s+//xs;
		}
		else {
			die "expected role name, got $rolelist";
		}
		
		if ($rolelist =~ /^\?/xs) {
			die 'unexpected question mark' if $kind eq 'class';
			$suffix = '?';
			$rolelist =~ s/^\?\s*//xs;
		}
		elsif ($rolelist =~ /^((?&PerlList)) $GRAMMAR/xso) {
			$role_params = $1;
			$rolelist =~ s/^\Q$role_params//xs;
			$rolelist =~ s/^\s+//xs;
		}
		
		if ($role_is_block) {
			push @return, sprintf('sprintf(q(%s%%s%s), scalar(do %s))', $prefix, $suffix, $role);
		}
		else {
			push @return, B::perlstring("$prefix$role$suffix");
		}
		if ($role_params) {
			push @return, sprintf('[%s]', $role_params);
		}
		
		$rolelist =~ s/^\s+//xs;
		if (length $rolelist) {
			$rolelist =~ /^,/ or die "expected comma, got $rolelist";
			$rolelist =~ s/^\,\s*//;
		}
	}
	
	return join(",", @return);
}

sub _handle_name_list {
	my ($me, $names) = @_;
	return unless $names;
	
	state $re = _fetch_re('MxpDecoratedIdentifierSolo');
	my @names = grep defined, ($names =~ /($re) $GRAMMAR/xg);
	return @names;
}

sub _handle_factory_keyword {
	my ($me, $name, $via, $code, $has_sig, $sig, $attrs) = @_;
	
	my $optim;
	for my $attr (@$attrs) {
		$optim = 1 if $attr =~ /^:optimize\b/;
	}
	
	if ($via) {
		return sprintf(
			'q[%s]->_factory(%s, \\(%s));',
			$me,
			($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
			($via  =~ /^\{/ ? "scalar(do $via)"  : B::perlstring($via)),
		);
	}
	if (!$has_sig) {
		my $munged_code = sprintf('sub { my ($factory, $class) = (@_); do %s }', $code);
		return sprintf(
			'q[%s]->_factory(%s, { caller => __PACKAGE__, code => %s, optimize => %d });',
			$me,
			($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
			$optim ? B::perlstring($munged_code) : $munged_code,
			!!$optim,
		);
	}
	my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
	my $munged_code = sprintf('sub { my($factory,$class,%s)=(shift,shift,@_); %s; do %s }', $signature_var_list, $extra, $code);
	sprintf(
		'q[%s]->_factory(%s, { caller => __PACKAGE__, code => %s, named => %d, signature => %s, optimize => %d });',
		$me,
		($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
		$optim ? B::perlstring($munged_code) : $munged_code,
		!!$signature_is_named,
		$type_params_stuff,
		!!$optim,
	);
}

sub _handle_method_keyword {
	my $me = shift;
	my ($name, $code, $has_sig, $sig, $attrs) = @_;
	
	my $optim;
	for my $attr (@$attrs) {
		$optim = 1 if $attr =~ /^:optimize\b/;
	}
	
	my $lex_name;
	if (defined $name and $name =~ /^\$(.+)$/) {
		$lex_name = $name;
	}
	
	my $return = '';
	
	if (defined $name and not defined $lex_name) {
		if ($has_sig) {
			my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
			my $munged_code = sprintf('sub { my($self,%s)=(shift,@_); %s; my $class = ref($self)||$self; do %s }', $signature_var_list, $extra, $code);
			$return = sprintf(
				'q[%s]->_can(%s, { caller => __PACKAGE__, code => %s, named => %d, signature => %s, optimize => %d });',
				$me,
				($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
				$optim ? B::perlstring($munged_code) : $munged_code,
				!!$signature_is_named,
				$type_params_stuff,
				!!$optim,
			);
		}
		else {
			my $munged_code = sprintf('sub { my $self = $_[0]; my $class = ref($self)||$self; do %s }', $code);
			$return = sprintf(
				'q[%s]->_can(%s, { caller => __PACKAGE__, code => %s, optimize => %d });',
				$me,
				($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
				$optim ? B::perlstring($munged_code) : $munged_code,
				!!$optim,
			);
		}
	}
	else {
		if ($has_sig) {
			my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
			my $munged_code = sprintf('sub { my($self,%s)=(shift,@_); %s; my $class = ref($self)||$self; do %s }', $signature_var_list, $extra, $code);
			$return = sprintf(
				'q[%s]->wrap_coderef({ caller => __PACKAGE__, code => %s, named => %d, signature => %s, optimize => %d });',
				'MooX::Press',
				$optim ? B::perlstring($munged_code) : $munged_code,
				!!$signature_is_named,
				$type_params_stuff,
				!!$optim,
			);
		}
		else {
			my $munged_code = sprintf('sub { my $self = $_[0]; my $class = ref($self)||$self; do %s }', $code);
			$return = sprintf(
				'q[%s]->wrap_coderef({ caller => __PACKAGE__, code => %s, optimize => %d });',
				'MooX::Press',
				$optim ? B::perlstring($munged_code) : $munged_code,
				!!$optim,
			);
		}
	}
	
	if ($lex_name) {
		return "my $lex_name = $return";
	}
	
	return $return;
}

sub _handle_multimethod_keyword {
	my $me = shift;
	my ($name, $code, $has_sig, $sig, $attrs) = @_;
	
	my $optim;
	my $extra_code = '';
	for my $attr (@$attrs) {
		$optim = 1 if $attr =~ /^:optimize\b/;
		$extra_code .= sprintf('alias=>%s', B::perlstring($1)) if $attr =~ /^:alias\((.+)\)$/;
	}
	
	if ($has_sig) {
		my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
		my $munged_code = sprintf('sub { my($self,%s)=(shift,@_); %s; my $class = ref($self)||$self; do %s }', $signature_var_list, $extra, $code);
		return sprintf(
			'q[%s]->_multimethod(%s, { caller => __PACKAGE__, code => %s, named => %d, signature => %s, %s });',
			$me,
			($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
			$munged_code,
			!!$signature_is_named,
			$type_params_stuff,
			$extra_code,
		);
	}
	else {
		my $munged_code = sprintf('sub { my $self = $_[0]; my $class = ref($self)||$self; do %s }', $code);
		return sprintf(
			'q[%s]->_multimethod(%s, { caller => __PACKAGE__, code => %s, named => 0, signature => sub { @_ }, %s });',
			$me,
			($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
			$munged_code,
			$extra_code,
		);
	}
}

sub _handle_modifier_keyword {
	my ($me, $kind, $names, $code, $has_sig, $sig, $attrs) = @_;

	my $optim;
	for my $attr (@$attrs) {
		$optim = 1 if $attr =~ /^:optimize\b/;
	}
	
	my @names = $me->_handle_name_list($names);
	
	my $processed_names =
		join q[, ],
		map { /^\{/ ? "scalar(do $_)" : B::perlstring($_) } @names;

	if ($has_sig) {
		my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
		my $munged_code;
		if ($kind eq 'around') {
			$munged_code = sprintf('sub { my($next,$self,%s)=(shift,shift,@_); %s; my $class = ref($self)||$self; do %s }', $signature_var_list, $extra, $code);
		}
		else {
			$munged_code = sprintf('sub { my($self,%s)=(shift,@_); %s; my $class = ref($self)||$self; do %s }', $signature_var_list, $extra, $code);
		}
		sprintf(
			'q[%s]->_modifier(q(%s), %s, { caller => __PACKAGE__, code => %s, named => %d, signature => %s, optimize => %d });',
			$me,
			$kind,
			$processed_names,
			$optim ? B::perlstring($munged_code) : $munged_code,
			!!$signature_is_named,
			$type_params_stuff,
			!!$optim,
		);
	}
	elsif ($kind eq 'around') {
		my $munged_code = sprintf('sub { my ($next, $self) = @_; my $class = ref($self)||$self; do %s }', $code);
		sprintf(
			'q[%s]->_modifier(q(%s), %s, { caller => __PACKAGE__, code => %s, optimize => %d });',
			$me,
			$kind,
			$processed_names,
			$optim ? B::perlstring($munged_code) : $munged_code,
			!!$optim,
		);
	}
	else {
		my $munged_code = sprintf('sub { my $self = $_[0]; my $class = ref($self)||$self; do %s }', $code);
		sprintf(
			'q[%s]->_modifier(q(%s), %s, { caller => __PACKAGE__, code => %s, optimize => %d });',
			$me,
			$kind,
			$processed_names,
			$optim ? B::perlstring($munged_code) : $munged_code,
			!!$optim,
		);
	}
}

sub _handle_package_keyword {
	my ($me, $kind, $name, $code, $has_sig, $sig, $plus, $opts) = @_;
	
	if ($kind eq 'abstract') {
		$kind = 'class';
		$code = "{ q[$me]->_abstract(1);  $code }";
	}
	
	if ($kind eq 'interface') {
		$kind = 'role';
		$code = "{ q[$me]->_interface(1); $code }";
	}
	
	if ($name and $has_sig) {
		my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
		my $munged_code = sprintf('sub { q(%s)->_package_callback(sub { my ($generator,%s)=(shift,@_); %s; do %s }, @_) }', $me, $signature_var_list, $extra, $code);
		sprintf(
			'use Zydeco::_Gather -parent => %s; use Zydeco::_Gather -gather, %s => { code => %s, named => %d, signature => %s }; use Zydeco::_Gather -unparent;',
			B::perlstring("$plus$name"),
			B::perlstring("$kind\_generator:$plus$name"),
			$munged_code,
			!!$signature_is_named,
			$type_params_stuff,
		);
	}
	elsif ($has_sig) {
		my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
		my $munged_code = sprintf('sub { q(%s)->_package_callback(sub { my ($generator,%s)=(shift,@_); %s; do %s }, @_) }', $me, $signature_var_list, $extra, $code);
		sprintf(
			'q[%s]->anonymous_generator(%s => { code => %s, named => %d, signature => %s }, toolkit => %s, prefix => %s, factory_package => %s, type_library => %s)',
			$me,
			$kind,
			$munged_code,
			!!$signature_is_named,
			$type_params_stuff,
			B::perlstring($opts->{toolkit}||'Moo'),
			B::perlstring($opts->{prefix}),
			B::perlstring($opts->{factory_package}),
			B::perlstring($opts->{type_library}),
		);
	}
	elsif ($name) {
		$code
			? sprintf(
				'use Zydeco::_Gather -parent => %s; use Zydeco::_Gather -gather, %s => q[%s]->_package_callback(sub %s); use Zydeco::_Gather -unparent;',
				B::perlstring("$plus$name"),
				B::perlstring("$kind:$plus$name"),
				$me,
				$code,
			)
			: sprintf(
				'use Zydeco::_Gather -gather, %s => {};',
				B::perlstring("$kind:$plus$name"),
			);
	}
	else {
		$code ||= '{}';
		sprintf(
			'q[%s]->anonymous_package(%s => sub { do %s }, toolkit => %s, prefix => %s, factory_package => %s, type_library => %s)',
			$me,
			$kind,
			$code,
			B::perlstring($opts->{toolkit}||'Moo'),
			B::perlstring($opts->{prefix}),
			B::perlstring($opts->{factory_package}),
			B::perlstring($opts->{type_library}),
		);
	}
}

sub _handle_has_keyword {
	my ($me, $names, $rawspec, $default) = @_;
	
	$rawspec = '()' if !defined $rawspec;
	
	if (defined $default and $default =~ /\$self/) {
		$rawspec = "lazy => !!1, default => sub { my \$self = \$_[0]; $default }, $rawspec";
	}
	elsif (defined $default) {
		$rawspec = "default => sub { $default }, $rawspec";
	}
	
	my @names = $me->_handle_name_list($names);
	
	my @r;
	for my $name (@names) {
		$name =~ s/^\+\*/+/;
		$name =~ s/^\*//;
		
		if ($name =~ /^\$(.+)$/) {
			my $display_name = $1;
			unshift @r, "my $name";
			push @r, sprintf(
				'q[%s]->_has(%s, is => "private", accessor => \\%s, %s)',
				$me,
				($display_name =~ /^\{/) ? "scalar(do $display_name)" : B::perlstring($display_name),
				$name,
				$rawspec,
			);
		}
		else {
			push @r, sprintf(
				'q[%s]->_has(%s, %s)',
				$me,
				($name =~ /^\{/) ? "scalar(do $name)" : B::perlstring($name),
				$rawspec,
			);
		}
	}
	join ";", @r;
}

sub _handle_requires_keyword {
	my ($me, $name, $has_sig, $sig) = @_;
	my $r1 = sprintf(
		'q[%s]->_requires(%s);',
		$me,
		($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
	);
	my $r2 = '';
	if (STRICT and $has_sig) {
		my ($signature_is_named, $signature_var_list, $type_params_stuff, $extra) = $me->_handle_signature_list($sig);
		$r2 = sprintf(
			'q[%s]->_modifier(q(around), %s, { caller => __PACKAGE__, code => %s, named => %d, signature => %s, optimize => %d });',
			$me,
			($name =~ /^\{/ ? "scalar(do $name)" : B::perlstring($name)),
			'sub { my $next = shift; goto $next }',
			!!$signature_is_named,
			$type_params_stuff,
			1,
		);
	}
	"$r1$r2";
}

sub _syntax_error {
	require Carp;
	if (ref $_[-1]) {
		my $ref = pop;
		my ($me, $kind, @poss) = @_;
		Carp::croak(
			"Unexpected syntax in $kind.\n" .
			"Expected:\n" .
			join("", map "\t$_\n", @poss) .
			"Got:\n" .
			"\t" . substr($$ref, 0, 32)
		);
	}
	else {
		my ($me, $kind, $msg) = @_;
		Carp::croak("Unexpected syntax in $kind.\n" . $msg);
	}
}

my $owed = 0;
sub _inject {
	my ($me, $ref, $trim_length, $new_code, $pad_at_end) = @_;
	$pad_at_end ||= 0;
	
	my @orig_lines = split /\n/, substr($$ref, 0, $trim_length), -1;
	my @new_lines  = split /\n/, $new_code, -1;
	
	if ($#orig_lines > $#new_lines) {
		my $diff = $#orig_lines - $#new_lines;
		if ($owed and $owed > $diff) {
			$owed -= $diff;
			$diff = 0;
		}
		elsif ($owed) {
			$diff -= $owed;
			$owed = 0;
		}
		my $prefix = "\n" x $diff;
		$new_code = $pad_at_end ? $new_code.$prefix : $prefix.$new_code;
	}
	elsif ($#orig_lines < $#new_lines) {
		$owed += ($#new_lines - $#orig_lines);
	}
	
	substr $$ref, 0, $trim_length, $new_code;
}

#
# KEYWORDS/UTILITIES
#

my @EXPORTABLES = qw(
	-booleans
	-privacy
	-utils
	-types
	-is
	-assert
	-features
	try
	class abstract role interface
	include toolkit begin end extends with requires
	has constant method multi factory before after around
	type_name coerce
	version authority overload
);

sub unimport {
	Keyword::Simple::undefine($_) for qw<
		class abstract role interface
		include toolkit begin end extends with requires
		has constant method multi factory before after around
		type_name coerce
	>;
	goto \&Exporter::Tiny::unimport;
}

sub import {
	no warnings 'closure';
	my ($me, %opts) = (shift, @_);
	my $caller = ($opts{caller} ||= caller);	
	require MooX::Press;
	'MooX::Press'->_apply_default_options(\%opts);
	
	my %want = map +($_ => 1), @{ $opts{keywords} || \@EXPORTABLES };
	
	# Optionally export wrapper subs for pre-declared types
	#
	if ($opts{declare}) {
		my $types = $opts{type_library};
		for my $name (@{ $opts{declare} }) {
			eval qq{
				sub $caller\::$name         ()   { goto \\&$types\::$name }
				sub $caller\::is_$name      (\$) { goto \\&$types\::is_$name }
				sub $caller\::assert_$name  (\$) { goto \\&$types\::assert_$name }
				1;
			} or die($@);
		}
	}
	
	# Export utility stuff
	#
	Zydeco::_Gather->import::into($caller, -gather => %opts);
	strict->import::into($caller);
	warnings->import::into($caller);
	MooX::Press::Keywords->import::into($caller, $_)
		for grep $want{$_}, qw(-booleans -privacy -util);
	Syntax::Keyword::Try->import::into($caller) if $want{try};
	if ($] >= 5.018) {
		feature->import::into($caller, qw( say state unicode_strings unicode_eval evalbytes current_sub fc ))
			if $want{-features};
	}
	elsif ($] >= 5.014) {
		feature->import::into($caller, qw( say state unicode_strings ))
			if $want{-features};
	}
	for my $library (qw/ Types::Standard Types::Common::Numeric Types::Common::String /) {
		$library->import::into($caller, $_)
			for grep $want{$_}, qw( -types -is -assert );
	}
	
	# `include` keyword
	#
	Keyword::Simple::define include => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpIncludeSyntax', anchor => 'start') or $me->_syntax_error(
			'include directive',
			'include <name>',
			$ref,
		);
		
		my ($pos, $name) = ($+[0], $+{name});
		my $qualified = 'MooX::Press'->qualify_name($name, $opts{prefix});
		$me->_inject($ref, $pos, sprintf('BEGIN { eval(q[%s]->_include(%s)) or die($@) };', $me, B::perlstring($qualified)));
	} if $want{include};

	# `class` keyword
	#
	Keyword::Simple::define class => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpClassSyntax', anchor => 'start') or $me->_syntax_error(
			'class declaration',
			'class <name> (<signature>) { <block> }',
			'class <name> { <block> }',
			'class <name>',
			'class (<signature>) { <block> }',
			'class { <block> }',
			'class;',
			$ref,
		);
		
		my ($pos, $plus, $name, $sig, $block) = ($+[0], $+{plus}, $+{name}, $+{sig}, $+{block});
		my $has_sig = !!exists $+{sig};
		$plus  ||= '';
		$block ||= '{}';
		
		$me->_inject($ref, $pos, "\n#\n#\n#\n#\n".$me->_handle_package_keyword(class => $name, $block, $has_sig, $sig, $plus, \%opts), 1);
	} if $want{class};

	Keyword::Simple::define abstract => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpAbstractSyntax', anchor => 'start') or $me->_syntax_error(
			'abstract class declaration',
			'abstract class <name> (<signature>) { <block> }',
			'abstract class <name> { <block> }',
			'abstract class <name>',
			'abstract class (<signature>) { <block> }',
			'abstract class { <block> }',
			'abstract class;',
			$ref,
		);
		
		my ($pos, $plus, $name, $sig, $block) = ($+[0], $+{plus}, $+{name}, $+{sig}, $+{block});
		my $has_sig = !!exists $+{sig};
		$plus  ||= '';
		$block ||= '{}';
		
		$me->_inject($ref, $pos, $me->_handle_package_keyword(abstract => $name, $block, $has_sig, $sig, $plus, \%opts), 1);
	} if $want{abstract};

	for my $kw (qw/ role interface /) {
		Keyword::Simple::define $kw => sub {
			my $ref = shift;
			
			$$ref =~ _fetch_re('MxpRoleSyntax', anchor => 'start') or $me->_syntax_error(
				"$kw declaration",
				"$kw <name> (<signature>) { <block> }",
				"$kw <name> { <block> }",
				"$kw <name>",
				"$kw (<signature>) { <block> }",
				"$kw { <block> }",
				"$kw;",
				$ref,
			);
			
			my ($pos, $name, $sig, $block) = ($+[0], $+{name}, $+{sig}, $+{block});
			my $has_sig = !!exists $+{sig};
			$block ||= '{}';
			
			$me->_inject($ref, $pos, $me->_handle_package_keyword($kw => $name, $block, $has_sig, $sig, '', \%opts), 1);
		} if $want{$kw};
	}

	Keyword::Simple::define toolkit => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpToolkitSyntax', anchor => 'start') or $me->_syntax_error(
			'toolkit declaration',
			'toolkit <toolkit> (<extensions>)',
			'toolkit <toolkit>;',
			$ref,
		);
		
		my ($pos, $name, $imports) = ($+[0], $+{name}, $+{imports});
		
		if ($imports) {
			my @imports = grep defined,
				($imports =~ / ((?&PerlQualifiedIdentifier)|(?&PerlComma)) $GRAMMAR /xg);
			my @processed_imports;
			while (@imports) {
				no warnings 'uninitialized';
				my $next = shift @imports;
				if ($next =~ /^::(.+)$/) {
					push @processed_imports, $1;
				}
				elsif ($next =~ /^[^\W0-9]/) {
					push @processed_imports, sprintf('%sX::%s', $name, $next);
				}
				else {
					die "Expected package name, got $next";
				}
				$imports[0] eq ',' and shift @imports;
			}
			$me->_inject($ref, $pos, sprintf('q[%s]->_toolkit(%s);', $me, join ",", map(B::perlstring($_), $name, @processed_imports)));
		}
		
		else {
			$me->_inject($ref, $pos, sprintf('q[%s]->_toolkit(%s);', $me, B::perlstring($name)));
		}
	} if $want{toolkit};

	# `begin` and `end` keywords
	#
	for my $kw (qw/ begin end /) {
		Keyword::Simple::define $kw => sub {
			my $ref = shift;
			
			$$ref =~ _fetch_re('MxpHookSyntax', anchor => 'start') or $me->_syntax_error(
				"$kw hook",
				"$kw { <block> }",
				$ref,
			);
			
			my ($pos, $capture) = ($+[0], $+{hook});
			$me->_inject($ref, $pos, sprintf('q[%s]->_begin(sub { my ($package, $kind) = (shift, @_); do %s });', $me, $capture));
		} if $want{$kw};
	}
	
	# `type_name` keyword
	#
	Keyword::Simple::define type_name => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpTypeNameSyntax', anchor => 'start') or $me->_syntax_error(
			'type name declaration',
			'type_name <identifier>',
			$ref,
		);
		
		my ($pos, $capture) = ($+[0], $+{name});
		$me->_inject($ref, $pos, sprintf('q[%s]->_type_name(%s);', $me, B::perlstring($capture)));
	} if $want{type_name};
	
	# `extends` keyword
	#
	Keyword::Simple::define extends => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpExtendsSyntax', anchor => 'start') or $me->_syntax_error(
			'extends declaration',
			'extends <classes>',
			$ref,
		);
		
		my ($pos, $capture) = ($+[0], $+{list});
		$me->_inject($ref, $pos, sprintf('q[%s]->_extends(%s);', $me, $me->_handle_role_list($capture, 'class')));
	} if $want{extends};
	
	# `with` keyword
	#
	Keyword::Simple::define with => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpWithSyntax', anchor => 'start') or $me->_syntax_error(
			'with declaration',
			'with <roles>',
			$ref,
		);
		
		my ($pos, $capture) = ($+[0], $+{list});
		
		$me->_inject($ref, $pos, sprintf('q[%s]->_with(%s);', $me, $me->_handle_role_list($capture, 'role')));
	} if $want{with};
	
	# `requires` keyword
	#
	Keyword::Simple::define requires => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpRequiresSyntax', anchor => 'start') or $me->_syntax_error(
			'requires declaration',
			'requires <name> (<signature>)',
			'requires <name>',
			$ref,
		);
		
		my ($pos, $name, $sig) = ($+[0], $+{name}, $+{sig});
		my $has_sig = !!exists $+{sig};
		$me->_inject($ref, $pos, $me->_handle_requires_keyword($name, $has_sig, $sig));
	} if $want{requires};
	
	# `has` keyword
	#
	Keyword::Simple::define has => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpHasSyntax', anchor => 'start') or $me->_syntax_error(
			'attribute declaration',
			'has <names> (<spec>) = <default>',
			'has <names> (<spec>)',
			'has <names> = <default>',
			'has <names>',
			$ref,
		);
		
		my ($pos, $name, $spec, $default) = ($+[0],  $+{name}, $+{spec}, $+{default});
		my $has_spec    = !!exists $+{spec};
		my $has_default = !!exists $+{default};
		$me->_inject($ref, $pos, $me->_handle_has_keyword($name, $has_spec ? $spec : undef, $has_default ? $default : undef));
	} if $want{has};
	
	# `constant` keyword
	#
	Keyword::Simple::define constant => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpConstantSyntax', anchor => 'start') or $me->_syntax_error(
			'constant declaration',
			'constant <name> = <value>',
			$ref,
		);
		
		my ($pos, $name, $expr) = ($+[0], $+{name}, $+{expr});
		$me->_inject($ref, $pos, sprintf('q[%s]->_constant(%s, %s);', $me, B::perlstring($name), $expr));
	} if $want{constant};
	
	# `method` keyword
	#
	Keyword::Simple::define method => sub {
		my $ref = shift;
		
		state $re_attr = _fetch_re('MxpAttribute');
		
		$$ref =~ _fetch_re('MxpMethodSyntax', anchor => 'start') or $me->_syntax_error(
			'method declaration',
			'method <name> <attributes> (<signature>) { <block> }',
			'method <name> (<signature>) { <block> }',
			'method <name> <attributes> { <block> }',
			'method <name> { <block> }',
			'method <attributes> (<signature>) { <block> }',
			'method (<signature>) { <block> }',
			'method <attributes> { <block> }',
			'method { <block> }',
			$ref,
		);
		
		my ($pos, $name, $attributes, $sig, $code) = ($+[0], $+{name}, $+{attributes}, $+{sig}, $+{code});
		my $has_sig = !!exists $+{sig};
		my @attrs   = $attributes ? grep(defined, ( ($attributes) =~ /($re_attr)/xg )) : ();
		
		$me->_inject($ref, $pos, $me->_handle_method_keyword($name, $code, $has_sig, $sig,  \@attrs));
	} if $want{method};

	# `multi` keyword
	#
	Keyword::Simple::define multi => sub {
		my $ref = shift;
		
		state $re_attr = _fetch_re('MxpAttribute');
		
		$$ref =~ _fetch_re('MxpMultiSyntax', anchor => 'start') or $me->_syntax_error(
			'multimethod declaration',
			'multi method <name> <attributes> (<signature>) { <block> }',
			'multi method <name> (<signature>) { <block> }',
			'multi method <name> <attributes> { <block> }',
			'multi method <name> { <block> }',
			$ref,
		);
		
		my ($pos, $name, $attributes, $sig, $code) = ($+[0], $+{name}, $+{attributes}, $+{sig}, $+{code});
		my $has_sig = !!exists $+{sig};
		my @attrs   = $attributes ? grep(defined, ( ($attributes) =~ /($re_attr)/xg )) : ();
		
		$me->_inject($ref, $pos, $me->_handle_multimethod_keyword($name, $code, $has_sig, $sig, \@attrs));
	} if $want{multi};

	# `before`, `after`, and `around` keywords
	#
	for my $kw (qw( before after around )) {
		Keyword::Simple::define $kw => sub {
			my $ref = shift;
			
			state $re_attr = _fetch_re('MxpAttribute');
		
			$$ref =~ _fetch_re('MxpModifierSyntax', anchor => 'start') or $me->_syntax_error(
				"$kw method modifier declaration",
				"$kw <names> <attributes> (<signature>) { <block> }",
				"$kw <names> (<signature>) { <block> }",
				"$kw <names> <attributes> { <block> }",
				"$kw <names> { <block> }",
				$ref,
			);
			
			my ($pos, $name, $attributes, $sig, $code) = ($+[0], $+{name}, $+{attributes}, $+{sig}, $+{code});
			my $has_sig = !!exists $+{sig};
			my @attrs   = $attributes ? grep(defined, ( ($attributes) =~ /($re_attr)/xg )) : ();
			
			$me->_inject($ref, $pos, $me->_handle_modifier_keyword($kw, $name, $code, $has_sig, $sig, \@attrs));
		} if $want{$kw};
	}
	
	Keyword::Simple::define factory => sub {
		my $ref = shift;
		
		if ( $$ref =~ _fetch_re('MxpFactorySyntax', anchor => 'start') ) {
			state $re_attr = _fetch_re('MxpAttribute');
			my ($pos, $name, $attributes, $sig, $code) = ($+[0], $+{name}, $+{attributes}, $+{sig}, $+{code});
			my $has_sig = !!exists $+{sig};
			my @attrs   = $attributes ? grep(defined, ( ($attributes) =~ /($re_attr)/xg )) : ();
			$me->_inject($ref, $pos, $me->_handle_factory_keyword($name, undef, $code, $has_sig, $sig, \@attrs));
			return;
		}
		
		$$ref =~ _fetch_re('MxpFactoryViaSyntax', anchor => 'start') or $me->_syntax_error(
			'factory method declaration',
			'factory <name> <attributes> (<signature>) { <block> }',
			'factory <name> (<signature>) { <block> }',
			'factory <name> <attributes> { <block> }',
			'factory <name> { <block> }',
			'factory <name> via <methodname>',
			'factory <name>',
			$ref,
		);
		
		my ($pos, $name, $via) = ($+[0], $+{name}, $+{via});
		$via ||= 'new';
		$me->_inject($ref, $pos, $me->_handle_factory_keyword($name, $via, undef, undef, undef, []));
	} if $want{factory};
	
	Keyword::Simple::define coerce => sub {
		my $ref = shift;
		
		$$ref =~ _fetch_re('MxpCoerceSyntax', anchor => 'start') or $me->_syntax_error(
			'coercion declaration',
			'coerce from <type> via <method_name> { <block> }',
			'coerce from <type> via <method_name>',
			$ref,
		);
		
		my ($pos, $from, $via, $code) = ($+[0], $+{from}, $+{via}, $+{code});
		if ($from =~ /^\{/) {
			$from = "scalar(do $from)"
		}
		elsif ($from !~ /^(q\b)|(qq\b)|"|'/) {
			$from = B::perlstring($from);
		}
		if ($via =~ /^\{/) {
			$via = "scalar(do $via)"
		}
		elsif ($via !~ /^(q\b)|(qq\b)|"|'/) {
			$via = B::perlstring($via);
		}
		
		$me->_inject($ref, $pos, sprintf('q[%s]->_coerce(%s, %s, %s);', $me, $from, $via, $code ? "sub { my \$class; local \$_; (\$class, \$_) = \@_; do $code }" : ''));
	} if $want{coerce};
		
	# Go!
	#
	on_scope_end {
		eval "package $caller; use Zydeco::_Gather -go; 1"
			or Carp::croak($@);
	};
	
	# Need this to export `authority` and `version`...
	@_ = ($me);
	push @_, grep $want{$_}, @Zydeco::EXPORT;
	goto \&Exporter::Tiny::import;
}

our %OPTS;

# `version` keyword
#
sub version {
	$OPTS{version} = shift;
}

# `authority` keyword
#
sub authority {
	$OPTS{authority} = shift;
}

# `overload` keyword
#
sub overload {
	if (@_ == 1 and ref($_[0]) eq 'HASH') {
		push @{ $OPTS{overload} ||= [] }, %{+shift};
	}
	elsif (@_ == 1 and ref($_[0]) eq 'ARRAY') {
		push @{ $OPTS{overload} ||= [] }, @{+shift};
	}
	else {
		push @{ $OPTS{overload} ||= [] }, @_;
	}
}

# `Zydeco::PACKAGE_SPEC` keyword
#
sub PACKAGE_SPEC { \%OPTS }


#
# CALLBACKS
#

sub _package_callback {
	shift;
	my $cb = shift;
	local %OPTS = (in_package => 1);
	&$cb;
	delete $OPTS{in_package};
#	use Data::Dumper;
#	$Data::Dumper::Deparse = 1;
#	print "OPTS:".Dumper $cb, +{ %OPTS };
	return +{ %OPTS };
}
sub _has {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('attribute declaration', 'Not supported outside class or role');
	my ($attr, %spec) = @_;
	$OPTS{has}{$attr} = \%spec;
}
sub _extends {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('extends declaration', 'Not supported outside class');
	@{ $OPTS{extends}||=[] } = @_;
}
sub _type_name {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('extends declaration', 'Not supported outside class or role');
	$OPTS{type_name} = shift;
}
sub _begin {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('begin hook', 'Not supported outside class or role (use import option instead)');
	$OPTS{begin} = shift;
}
sub _end {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('end hook', 'Not supported outside class or role (use import option instead)');
	$OPTS{end} = shift;
}
sub _interface {
	shift;
	$OPTS{interface} = shift;
}
sub _abstract {
	shift;
	$OPTS{abstract} = shift;
}
sub _with {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('with declaration', 'Not supported outside class or role');
	push @{ $OPTS{with}||=[] }, @_;
}
sub _toolkit {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('toolkit declaration', 'Not supported outside class or role (use import option instead)');
	my ($toolkit, @imports) = @_;
	$OPTS{toolkit} = $toolkit;
	push @{ $OPTS{import}||=[] }, @imports if @imports;
}
sub _requires {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('requires declaration', 'Not supported outside role');
	push @{ $OPTS{requires}||=[] }, @_;
}
sub _coerce {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('coercion declaration', 'Not supported outside class');
	push @{ $OPTS{coerce}||=[] }, @_;
}
sub _factory {
	my $me = shift;
	$OPTS{in_package} or $me->_syntax_error('factory method declaration', 'Not supported outside class');
	push @{ $OPTS{factory}||=[] }, @_;
}
sub _constant {
	my $me = shift;
	my ($name, $value) = @_;
	if (! $OPTS{in_package}) {
		'MooX::Press'->install_constants(scalar(caller), { $name => $value });
		return;
	}
	$OPTS{constant}{$name} = $value;
}
sub _can {
	my $me = shift;
	my ($name, $code) = @_;
	if (! $OPTS{in_package}) {
		'MooX::Press'->install_methods(scalar(caller), { $name => $code });
		return;
	}
	$OPTS{can}{$name} = $code;
}
sub _multimethod {
	my $me = shift;
	my ($name, $spec) = @_;
	if (! $OPTS{in_package}) {
		'MooX::Press'->install_multimethod(scalar(caller), 'class', $name, $spec);
		return;
	}
	push @{ $OPTS{multimethod} ||= [] }, $name => $spec;
}
sub _modifier {
	my $me = shift;
	my ($kind, @args) = @_;
	if (! $OPTS{in_package}) {
		my $codelike = pop @args;
		my $coderef  = 'MooX::Press'->_prepare_method_modifier(scalar(caller), $kind, \@args, $codelike);
		require Class::Method::Modifiers;
		Class::Method::Modifiers::install_modifier(scalar(caller), $kind, @args, $coderef);
	}
	push @{ $OPTS{$kind} ||= [] }, @args;
}
sub _include {
	my $me = shift;
	$OPTS{in_package} and $me->_syntax_error('include directive', 'Not supported inside class or role');
	
	require Path::ScanINC;
	my @chunks = split /::/, $_[0];
	$chunks[-1] .= '.pl';
	my $file = Path::ScanINC->new->first_file(@chunks);
	
	if (!$file) {
		require Carp;
		Carp::croak("No such file: " . join("/", @chunks));
	}
	
	ref $file eq 'ARRAY' and die "not supported yet";
	my $code = $file->slurp_utf8;
	
	sprintf(
		"do {\n# line 1 %s\n%s\n};\n1;\n",
		B::perlstring($file),
		$code,
	);
}

#{
#	package Zydeco::Anonymous::Package;
#	our $AUTHORITY = 'cpan:TOBYINK';
#	our $VERSION   = '0.500';
#	use overload q[""] => sub { ${$_[0]} }, fallback => 1;
#	sub DESTROY {}
#	sub AUTOLOAD {
#		my $me = shift;
#		(my $method = our $AUTOLOAD) =~ s/.*:://;
#		$$me->$method(@_);
#	}
#	
#	package Zydeco::Anonymous::Class;
#	our $AUTHORITY = 'cpan:TOBYINK';
#	our $VERSION   = '0.500';
#	our @ISA       = qw(Zydeco::Anonymous::Package);
#	sub new {
#		my $me = shift;
#		$$me->new(@_);
#	}
#	use overload q[&{}] => sub {
#		my $me = shift;
#		sub { $me->new(@_) }
#	};
#	
#	package Zydeco::Anonymous::Role;
#	our $AUTHORITY = 'cpan:TOBYINK';
#	our $VERSION   = '0.500';
#	our @ISA       = qw(Zydeco::Anonymous::Package);
#	
#	package Zydeco::Anonymous::ParameterizableClass;
#	our $AUTHORITY = 'cpan:TOBYINK';
#	our $VERSION   = '0.500';
#	our @ISA       = qw(Zydeco::Anonymous::Package);
#	sub generate_package {
#		my $me  = shift;
#		my $gen = $$me->generate_package(@_);
#		bless \$gen, 'Zydeco::Anonymous::Class';
#	}
#	use overload q[&{}] => sub {
#		my $me = shift;
#		sub { $me->new_class(@_) }
#	};
#
#	package Zydeco::Anonymous::ParameterizableRole;
#	our $AUTHORITY = 'cpan:TOBYINK';
#	our $VERSION   = '0.500';
#	our @ISA       = qw(Zydeco::Anonymous::Package);
#	sub generate_package {
#		my $me  = shift;
#		my $gen = $$me->generate_package(@_);
#		bless \$gen, 'Zydeco::Anonymous::Class';
#	}
#	use overload q[&{}] => sub {
#		my $me = shift;
#		sub { $me->new_role(@_) }
#	};
#}

my $i = 0;
sub anonymous_package {
	my $me = shift;
	my ($kind, $callback, %opts) = @_;
	my $package_dfn = $me->_package_callback($callback);
	
	for my $forbidden (qw/ factory type_name coerce /) {
		die if exists $package_dfn->{$forbidden};
	}
	$package_dfn->{type_name}  = undef;
	$package_dfn->{factory}    = undef;
	
	my $qname = sprintf('%s::__ANON_%06d__', __PACKAGE__, ++$i);
	
	require MooX::Press;
	my $method = "make_$kind";
	MooX::Press->$method("::$qname", %opts, %$package_dfn);
	
	require Module::Runtime;
	$INC{Module::Runtime::module_notional_filename($qname)} = __FILE__;
	#return bless(\$qname, "Zydeco::Anonymous::".ucfirst($kind));
	return $qname;
}

sub anonymous_generator {
	my $me = shift;
	my ($kind, $callback, %opts) = @_;
	my $qname = sprintf('%s::__ANON_%06d__', __PACKAGE__, ++$i);
	
	require MooX::Press;
	my $method = "make_$kind\_generator";
	MooX::Press->$method("::$qname", %opts, generator => $callback);
	
	require Module::Runtime;
	$INC{Module::Runtime::module_notional_filename($qname)} = __FILE__;
	#return bless(\$qname, "Zydeco::Anonymous::Parameterizable".ucfirst($kind));
	return $qname;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Zydeco - Jazz up your Perl

=head1 SYNOPSIS

MyApp.pm

  use v5.14;
  use strict;
  use warnings;
  
  package MyApp {
    use Zydeco;
    
    class Person {
      has name   ( type => Str, required => true );
      has gender ( type => Str );
      
      factory new_man (Str $name) {
        return $class->new(name => $name, gender => 'male');
      }
      
      factory new_woman (Str $name) {
        return $class->new(name => $name, gender => 'female');
      }
      
      method greet (Person *friend, Str *greeting = "Hello") {
        printf("%s, %s!\n", $arg->greeting, $arg->friend->name);
      }
      
      coerce from Str via from_string {
        return $class->new(name => $_);
      }
    }
  }

my_script.pl

  use v5.14;
  use strict;
  use warnings;
  use MyApp;
  use MyApp::Types qw( is_Person );
  
  # Create a new MyApp::Person object.
  #
  my $alice  = MyApp->new_woman("Alice");
  is_Person($alice) or die;
  
  # The string "Bob" will be coerced to a MyApp::Person.
  #
  $alice->greet(friend => "Bob", greeting => 'Hi');

=head1 DESCRIPTION

Zydeco is a Perl module to jazz up your object-oriented programming.
It fuses together:

=over

=item *

Classes, roles, and interfaces, including parameterizable classes and roles
(a.k.a. class generators and role generators).

=item *

Factories to help your objects make other objects.

=item *

Methods with signatures, type constraints, and coercion.

=item *

Method modifiers to easily wrap or override inherited methods.

=item *

Multimethods.

=item *

Powerful delegation features.

=item *

True private methods and attributes.

=item *

Syntactic sugar as sweet as pecan pie.

=back

=head2 Important Concepts

=head3 The Factory Package and Prefix

Zydeco assumes that all the classes and roles you are building
with it will be defined under the same namespace B<prefix>. For example
"MyApp::Person" and "MyApp::Company" are both defined under the common
prefix of "MyApp".

It also assumes there will be a B<< factory package >> that can be used
to build new instances of your class. Rather than creating a new person
object with C<< MyApp::Person->new() >>, you should create a new person
object with C<< MyApp->new_person() >>. Calling C<< MyApp::Person->new() >>
directly is only encouraged from within the "MyApp::Person" class itself,
and from within the factory. Everywhere else, you should call
C<< MyApp->new_person() >> instead.

By default, the factory package and the prefix are the same: they are
the caller that you imported Zydeco into. But they can be set
to whatever:

  use Zydeco (
    prefix          => 'MyApp::Objects',
    factory_package => 'MyApp::Makers',
  );

Zydeco assumes that you are defining all the classes and roles
within this namespace prefix in a single Perl module file. This Perl
module file would normally be named based on the prefix, so in the
example above, it would be "MyApp/Objects.pm" and in the example from
the SYNOPSIS, it would be "MyApp.pm".

But see also the documentation for C<include>.

Of course, there is nothing to stop you from having multiple prefixes
for different logical parts of a larger codebase, but Zydeco
assumes that if it's been set up for a prefix, it owns that prefix and
everything under it, and it's all defined in the same Perl module.

Each object defined by Zydeco will have a C<FACTORY> method,
so you can do:

  $person_object->FACTORY

And it will return the string "MyApp". This allows for stuff like:

  class Person {
    method give_birth {
      return $self->FACTORY->new_person();
    }
  }

=head3 The Type Library

While building your classes and objects, Zydeco will also build
type constraints for each of them. So for the "MyApp::Person" class
above, it also builds a B<Person> type constraint. This can be used
in Moo/Moose attribute definitions like:

  use MyApp;
  use MyApp::Types qw( Person );
  
  use Moose;
  has boss => (is => 'rw', isa => Person);

And just anywhere a type constraint may be used generally. You should
know this stuff by now.

Note that we had to C<use MyApp> before we could C<use MyApp::Types>.
This is because there isn't a physical "MyApp/Types.pm" file on disk;
it is defined entirely by "MyApp.pm".

Your type library will be the same as your namespace prefix, with
"::Types" added at the end. But you can change that:

  use Zydeco (
    prefix          => 'MyApp::Objects',
    factory_package => 'MyApp::Makers',
    type_library    => 'MyApp::TypeLibrary',
  );

It can sometimes be helpful to pre-warn Zydeco about the
types you're going to define before you define them, just so it
is able to allow them as barewords in some places...

  use Zydeco (
    prefix          => 'MyApp::Objects',
    factory_package => 'MyApp::Makers',
    type_library    => 'MyApp::TypeLibrary',
    declare         => [qw( Person Company )],
  );

See also L<Type::Tiny::Manual>.

=head1 KEYWORDS

=head2 C<< class >>

Define a very basic class:

  class Person;

Define a more complicated class:

  class Person {
    ...;
  }

Note that for the C<class> keyword without a block, it does I<not> act like
the C<package> keyword by changing the "ambient" package. It just defines a
totally empty class with no methods or attributes.

The prefix will automatically be added to the class name, so if the prefix
is MyApp, the above will create a class called MyApp::Person. It will also
create a factory method C<< MyApp->new_person >>. (The name is generated by
stripping the prefix from the class name, replacing any "::" with an
underscore, lowercasing, and prefixing it with "new_".) And it will create
a type called B<Person> in the type library. (Same rules to generate the
name apart from lowercasing and adding "new_".)

Classes can be given more complex names:

  class Person::Neanderthal {
    ...;
  }

Will create "MyApp::Person::Neanderthal" class, a factory method called
C<< MyApp->new_person_neanderthal >>, and a B<Person_Neanderthal> type.

It is possible to create a class without the prefix:

  class ::Person {
    ...;
  }

The class name will now be "Person" instead of "MyApp::Person"!

=head3 Nested classes

C<class> blocks can be nested. This establishes an inheritance heirarchy.

  class Animal {
    has name;
    class Mammal {
      class Primate {
        class Monkey;
        class Gorilla;
        class Human {
          class Superhuman;
        }
      }
    }
    class Bird;
    class Fish {
      class Shark;
    }
  }
  
  my $superman = MyApp->new_superhuman( name => 'Kal El' );

See also C<extends> as an alternative way of declaring inheritance.

It is possible to prefix a class name with a plus sign:

  package MyApp {
    use Zydeco;
    class Person {
      has name;
      class +Employee {
        has job_title;
      }
    }
  }

Now the employee class will be named C<MyApp::Person::Employee> instead of
the usual C<MyApp::Employee>.

=head3 Abstract classes

Classes can be declared as abstract:

  package MyApp {
    use Zydeco;
    abstract class Animal {
      class Cat;
      class Dog;
    }
  }

For abstract classes, there is no constructor or factory, so you cannot create
an Animal instance directly; but you can create instances of the subclasses.
It is usually better to use roles than abstract classes, but sometimes the
abstract class makes more intuitive sense.

=head2 C<< role >>

Define a very basic role:

  role Person;

Define a more complicated role:

  role Person {
    ...;
  }

This is just the same as C<class> but defines a role instead of a class.

Roles cannot be nested within each other, nor can roles be nested in classes,
nor classes in roles.

=head2 C<< interface >>

An interface is a lightweight role. It cannot define attributes, methods,
multimethods, or method modifiers, but otherwise functions as a role.
(It may have C<requires> statements and define constants.)

  package MyApp;
  use Zydeco;
  
  interface Serializer {
    requires serialize;
  }
  
  interface Deserializer {
    requires deserialize;
  }
  
  class MyJSON {
    with Serializer, Deserialize;
    method serialize   ($value) { ... } 
    method deserialize ($value) { ... } 
  }
  
  my $obj = MyApp->new_myjson;
  $obj->does('MyApp::Serializer');   # true

=head2 C<< toolkit >>

Use a different toolkit instead of Moo.

  # use Mouse
  class Foo {
    toolkit Mouse;
  }
  
  # use Moose
  # use MooseX::Aliases
  # use MooseX::StrictConstructor
  class Bar {
    toolkit Moose ( Aliases, StrictConstructor );
  }

You can of course specify you want to use Moo:

  class Baz {
    toolkit Moo;
  }

Not all MooseX/MouseX/MooX packages will work, but *X::StrictConstructor will.

Although it is not possible to use the C<toolkit> keyword outside of
C<class>, C<abstract class>, C<role>, and C<interface> blocks, it is
possible to specify a default toolkit when you import Zydeco.

  use Zydeco (
    ...,
    toolkit => 'Moose',
  );

  use Zydeco (
    ...,
    toolkit => 'Mouse',
  );

=head2 C<< extends >>

Defines a parent class. Only for use within C<class> and C<abstract class>
blocks.

  class Person {
    extends Animal;
  }

This works:

  class Person {
    extends ::Animal;   # no prefix
  }

=head2 C<< with >>

Composes roles and interfaces.

  class Person {
    with Employable, Consumer;
  }
  
  role Consumer;
  
  role Worker;
  
  role Payable;
  
  role Employable {
    with Worker, Payable;
  }

It is possible to compose a role which does not have its own definition by
adding a question mark to the end of the name:

  class Person {
    with Employable, Consumer?;
  }
  
  role Employable {
    with Worker?, Payable?;
  }

This is equivalent to declaring an empty role.

The C<with> keyword cannot be used outside of C<class>, C<abstract class>,
C<role>, and C<interface> blocks.

=head2 C<< begin >>

This code gets run early on in the definition of a class or role.

  class Person {
    begin {
      say "Defining $package";
    }
  }

At the time the code gets run, none of the class's attributes or methods will
be defined yet.

The lexical variables C<< $package >> and C<< $kind >> are defined within the
block. C<< $kind >> will be either 'class' or 'role'.

The C<begin> keyword cannot be used outside of C<class>, C<abstract class>,
C<role>, and C<interface> blocks, though it is possible to define a global
default for it:

  use Zydeco (
    ...,
    begin => sub {
      my ($package, $kind) = @_;
      ...;
    },
  );

Per-package C<begin> overrides the global C<begin>.

Unlike Perl's C<BEGIN> keyword, a package can only have one C<begin>.

If C<class> definitions are nested, C<begin> blocks will be inherited by
child classes. If a parent class is specified via C<extends>, C<begin>
blocks will not be inherited.

=head2 C<< end >>

This code gets run late in the definition of a class or role.

  class Person {
    end {
      say "Finished defining $package";
    }
  }

The lexical variables C<< $package >> and C<< $kind >> are defined within the
block. C<< $kind >> will be either 'class' or 'role'.

The C<end> keyword cannot be used outside of C<class>, C<abstract class>,
C<role>, and C<interface> blocks, though it is possible to define a global
default for it:

  use Zydeco (
    ...,
    end => sub {
      my ($package, $kind) = @_;
      ...;
    },
  );

Per-package C<end> overrides the global C<end>.

Unlike Perl's C<END> keyword, a package can only have one C<end>.

If C<class> definitions are nested, C<end> blocks will be inherited by
child classes. If a parent class is specified via C<extends>, C<end>
blocks will not be inherited.

=head2 C<< has >>

Defines an attribute.

  class Person {
    has name;
    has age;
  }
  
  my $bob = MyApp->new_person(name => "Bob", age => 21);

Cannot be used outside of C<class>, C<abstract class>, and C<role> blocks.

Moo-style attribute specifications may be given:

  class Person {
    has name ( is => rw, type => Str, required => true );
    has age  ( is => rw, type => Int );
  }

Note there is no fat comma after the attribute name! It is a bareword.

Use a plus sign before an attribute name to modify an attribute defined
in a parent class.

  class Animal {
    has name ( type => Str, required => false );
    
    class Person {
      has +name ( required => true );
    }
  }

C<rw>, C<rwp>, C<ro>, C<lazy>, C<bare>, C<private>, C<true>, and C<false>
are allowed as barewords for readability, but C<is> is optional, and defaults
to C<rw>.

The names of attributes can start with an asterisk:

  has *foo;

This adds no extra meaning, but is supported for consistency with the syntax
of named parameters in method signatures. (Depending on your text editor, it
may also improve syntax highlighting.)

If you need to decide an attribute name on-the-fly, you can replace the
name with a block that returns the name as a string.

  class Employee {
    extends Person;
    has {
      $ENV{LOCALE} eq 'GB'
        ? 'national_insurance_no'
        : 'social_security_no'
    } (type => Str)
  }
  
  my $bob = Employee->new(
    name               => 'Bob',
    social_security_no => 1234,
  );

You can think of the syntax as being kind of like C<print>.

  print BAREWORD_FILEHANDLE @strings;
  print { block_returning_filehandle(); } @strings;

The block is called in scalar context, so you'll need a loop to define a list
like this:

  class Person {
    my @attrs = qw( name age );
    
    # this does not work
    has {@attrs} ( required => true );
    
    # this works
    for my $attr (@attrs) {
      has {$attr} ( required => true );
    }
  }

=head3 Type constraints for attributes

Note C<type> instead of C<isa>. Any type constraints from L<Types::Standard>,
L<Types::Common::Numeric>, and L<Types::Common::String> will be avaiable as
barewords. Also, any pre-declared types can be used as barewords. It's
possible to quote types as strings, in which case you don't need to have
pre-declared them.

  class Person {
    has name   ( type => Str, required => true );
    has age    ( type => Int );
    has spouse ( type => 'Person' );
    has kids   (
      is      => lazy,
      type    => 'ArrayRef[Person]',
      builder => sub { [] },
    );
  }

Note that when C<type> is a string, Zydeco will consult your
type library to figure out what it means.

It is also possible to use C<< isa => 'SomeClass' >> or
C<< does => 'SomeRole' >> to force strings to be treated as class names
or role names instead of type names.

  class Person {
    has name   ( type => Str, required => true );
    has age    ( type => Int );
    has spouse ( isa  => 'Person' );
    has pet    ( isa  => '::Animal' );   # no prefix
  }

For enumerations, you can define them like this:

  class Person {
    ...;
    has status ( enum => ['alive', 'dead', 'undead'] );
  }

=head3 Delegation

Zydeco integrates support for L<MooX::Enumeration> (and
L<MooseX::Enumeration>, but MouseX::Enumeration doesn't exist).

  class Person {
    ...;
    has status (
      enum    => ['alive', 'dead', 'undead'],
      default => 'alive',
      handles => 1,
    );
  }
  
  my $bob = MyApp->new_person;
  if ( $bob->is_alive ) {
    ...;
  }

C<< handles => 1 >> creates methods named C<is_alive>, C<is_dead>, and
C<is_undead>, and C<< handles => 2 >> creates methods named
C<status_is_alive>, C<status_is_dead>, and C<status_is_undead>.

Checking C<< $bob->status eq 'alvie' >> is prone to typos, but
C<< $bob->status_is_alvie >> will cause a runtime error because the
method is not defined.

Zydeco also integrates support for L<Sub::HandlesVia> allowing
you to delegate certain methods to unblessed references and non-reference
values. For example:

  class Person {
    has age (
      type         => 'Int',
      default      => 0,
      handles_via  => 'Counter',
      handles      => {
        birthday => 'inc',   # increment age
      },
    );
    after birthday {
      if ($self->age < 30) {
        say "yay!";
      }
      else {
        say "urgh!";
      }
    }
  }

C<handles> otherwise works as you'd expect from Moo and Moose.

=head3 Required versus optional attributes and defaults

A trailing C<< ! >> indicates a required attribute.

  class Person {
    has name!;
  }

It is possible to give a default using an equals sign.

  class WidgetCollection {
    has name = "Widgets";
    has count (type => Num) = 0;
  }

Note that the default comes after the spec, so in cases where the spec is
long, it may be clearer to express the default inside the spec:

  class WidgetCollection {
    has name = "Widgets";
    has count (
      type     => Num,
      lazy     => true,
      required => false,
      default  => 0,
    );
  }

Defaults given this way will be eager (non-lazy), but can be made lazy using
the spec:

  class WidgetCollection {
    has name = "Widgets";
    has count (is => lazy) = 0;
  }

Defaults I<can> use the C<< $self >> object:

  class WidgetCollection {
    has name         = "Widgets";
    has display_name = $self->name;
  }

Any default that includes C<< $self >> will automatically be lazy, but can be
made eager using the spec. (It is almost certainly a bad idea to do so though.)

  class WidgetCollection {
    has name = "Widgets";
    has display_name ( lazy => false ) = $self->name;
  }

=head3 Specifying multiple attributes at once

Commas may be used to separate multiple attributes:

  class WidgetCollection {
    has name, display_name ( type => Str );
  }

The specification and defaults are applied to every attribute in the list.

=head3 Private attributes

If an attribute name starts with a dollar sign, it is a private (lexical)
attribute. Private attributes cannot be set in the constructor, and cannot
be directly accessed outside the class's lexical scope.

  class Foo {
    has $ua = HTTP::Tiny->new;
    
    method fetch_data ( Str $url ) {
      my $response = $self->$ua->get($url);
      $response->{is_success} or confess('request failed');
      return $response->{content};
    }
  }

Note how C<< $self->$ua >> is still called as a method. You don't just do
C<< $ua->get() >>. The invocant is still required, just like it would be
with a normal public attribute:

  class Foo {
    has ua = HTTP::Tiny->new;
    
    method fetch_data ( Str $url ) {
      my $response = $self->ua->get($url);
      $response->{is_success} or confess('request failed');
      return $response->{content};
    }
  }

Private attributes can have delegated methods (C<handles>):

  class Foo {
    has $ua (
      default => sub { HTTP::Tiny->new },
      handles => [
        http_get  => 'get',
        http_post => 'post',
      ],
    );
    
    method fetch_data ( Str $url ) {
      my $response = $self->http_get($url);
      $response->{is_success} or confess('request failed');
      return $response->{content};
    }
  }

These can even be made lexical too:

  class Foo {
    my ($http_get, $http_post);  # predeclare
    
    has $ua (
      default => sub { HTTP::Tiny->new },
      handles => [
        \$http_get  => 'get',
        \$http_post => 'post',
      ],
    );
    
    method fetch_data ( Str $url ) {
      my $response = $self->$http_get($url);
      $response->{is_success} or confess('request failed');
      return $response->{content};
    }
  }

Note how an arrayref is used for C<handles> instead of a hashref. This
is because scalarrefs don't work as hashref keys.

Although constructors ignore private attributes, you may set them in a
factory method.

  class Foo {
    has $ua;
    
    factory new_foo (%args) {
      my $instance = $class->new(%args);
      $instance->$ua( HTTP::Tiny->new );
      return $instance;
    }
  }

C<< has $foo >> is just a shortcut for:

  my $foo;
  has foo => (is => "private", accessor => \$foo);

You can use C<< is => "private" >> to create even I<more> private attributes
without even having that lexical accessor:

  has foo => (is => "private");

If it seems like an attribute that can't be set in the constructor and
doesn't have accessors would be useless, you're wrong. Because it can still
have delegations and a default value.

Private attributes use lexical variables, so are visible to subclasses
only if the subclass definition is nested in the base class.

=head2 C<< constant >>

Defines a constant.

  class Person {
    extends Animal;
    constant latin_name = 'Homo sapiens';
  }

C<< MyApp::Person->latin_name >>, C<< MyApp::Person::latin_name >>, and
C<< $person_object->latin_name >> will return 'Homo sapiens'.

Outside of C<class>, C<abstract class>, C<role>, and C<interface> blocks,
will define a constant in the caller package. (That is, usually the factory.)

=head2 C<< method >>

Defines a method.

  class Person {
    has spouse;
    
    method marry {
      my ($self, $partner) = @_;
      $self->spouse($partner);
      $partner->spouse($self);
      return $self;
    }
  }

C<< sub { ... } >> will not work as a way to define methods within the
class. Use C<< method { ... } >> instead.

Outside of C<class>, C<abstract class>, C<role>, and C<interface> blocks,
C<method> will define a method in the caller package. (Usually the factory.)

The variables C<< $self >> and C<< $class >> will be automatically defined
within all methods. C<< $self >> is set to C<< $_[0] >> (though the invocant
is not shifted off C<< @_ >>). C<< $class >> is set to C<< ref($self)||$self >>.
If the method is called as a class method, both C<< $self >> and C<< $class >>
will be the same thing: the full class name as a string. If the method is
called as an object method, C<< $self >> is the object and C<< $class >> is
its class.

Like with C<has>, you may use a block that returns a string instead of a
bareword name for the method.

  method {"ma"."rry"} {
    ...;
  }

Zydeco supports method signatures for named arguments and
positional arguments. A mixture of named and positional arguments
is allowed, with some limitations. For anything more complicates,
you should define the method with no signature at all, and unpack
C<< @_ >> within the body of the method.

=head3 Signatures for Named Arguments

  class Person {
    has spouse;
    
    method marry ( Person *partner, Object *date = DateTime->now ) {
      $self->spouse( $arg->partner );
      $arg->partner->spouse( $self );
      return $self;
    }
  }

The syntax for each named argument is:

  Type *name = default

The type is a type name, which will be parsed using L<Type::Parser>.
(So it can include the C<< ~ >>, C<< | >>, and C<< & >>, operators,
and can include parameters in C<< [ ] >> brackets. Type::Parser can
handle whitespace in the type, but not comments.

Alternatively, you can provide a block which returns a type name as a string
or returns a blessed Type::Tiny object. For very complex types, where you're
expressing additional coercions or value constraints, this is probably what
you want.

The asterisk indicates that the argument is named, not positional.

The name may be followed by a question mark to indicate an optional
argument.

  method marry ( Person *partner, Object *date? ) {
    ...;
  }

Or it may be followed by an equals sign to set a default value.

Comments may be included in the signature, but not in the middle of
a type constraint.

  method marry (
    # comment here is okay
    Person
    # comment here is fine too
    *partner
    # and here
  ) { ... }

  method marry (
    Person # comment here is not okay!
           | Horse
    *partner
  ) { ... }

As with signature-free methods, C<< $self >> and C<< $class >> wll be
defined for you in the body of the method. However, when a signature
has been used C<< $self >> I<is> shifted off C<< @_ >>.

Also within the body of the method, a variable called C<< $arg >>
is provided. This is a hashref of the named arguments. So you can
access the partner argument in the above example like this:

  $arg->{partner}

But because C<< $arg >> is blessed, you can also do:

  $arg->partner

The latter style is encouraged as it looks neater, plus it helps
catch typos. (C<< $ars->{pratner} >> for example!) However, accessing
it as a plain hashref is supported and shouldn't be considered to be
breaking encapsulation.

For optional arguments you can check:

  exists($arg->{date})

Or:

  $arg->has_date

For types which have a coercion defined, the value will be automatically
coerced.

Methods with named arguments can be called with a hash or hashref.

  $alice->marry(  partner => $bob  );      # okay
  $alice->marry({ partner => $bob });      # also okay

=head3 Signatures for Positional Arguments

  method marry ( Person $partner, Object $date? ) {
    $self->spouse( $partner );
    $partner->spouse( $self );
    return $self;
  }

The dollar sign is used instead of an asterisk to indicate a positional
argument.

As with named arguments, C<< $self >> is automatically shifted off C<< @_ >>
and C<< $class >> exists. Unlike named arguments, there is no C<< $arg >>
variable, and instead a scalar variable is defined for each named argument.

Optional arguments and defaults are supported in the same way as named
arguments.

It is possible to include a slurpy hash or array at the end of the list
of positional arguments.

  method marry ( $partner, $date, @vows ) {
    ...;
  }

If you need to perform a type check on the slurpy parameter, you should
pretend it is a hashref or arrayref.

  method marry ( $partner, $date, ArrayRef[Str] @vows ) {
    ...;
  }

=head3 Signatures with Mixed Arguments

You may mix named and positional arguments with the following limitations:

=over

=item *

Positional arguments must appear at the beginning and/or end of the list.
They cannot be surrounded by named arguments.

=item *

Positional arguments cannot be optional and cannot have a default. They
must be required. (Named arguments can be optional and have defaults.)

=item *

No slurpies!

=back

  method print_html ($tag, Str $text, *htmlver?, *xml?, $fh) {
  
    confess "update your HTML" if $arg->htmlver < 5;
    
    if (length $text) {
      print $fh "<tag>$text</tag>";
    }
    elsif ($arg->xml) {
      print $fh "<tag />";
    }
    else {
      print $fh "<tag></tag>";
    }
  }
  
  $obj->print_html('h1', 'Hello World', { xml => true }, \*STDOUT);
  $obj->print_html('h1', 'Hello World',   xml => true  , \*STDOUT);
  $obj->print_html('h1', 'Hello World',                  \*STDOUT);

Mixed signatures are basically implemented like named signatures, but
prior to interpreting C<< @_ >> as a hash, some parameters are spliced
off the head and tail. We need to know how many elements to splice off
each end, so that is why there are restrictions on slurpies and optional
parameters.

=head3 Empty Signatures

There is a difference between the following two methods:

  method foo {
    ...;
  }
  
  method foo () {
    ...;
  }

In the first, you have not provided a signature and are expected to
deal with C<< @_ >> in the body of the method. In the second, there
is a signature, but it is a signature showing that the method expects
no arguments (other than the invocant of course).

=head3 Optimizing Methods

For a slight compile-time penalty, you can improve the speed which
methods run at using the C<< :optimize >> attribute:

  method foo :optimize (...) {
    ...;
  }

Optimized methods must not close over any lexical (C<my> or C<our>)
variables; they can only access the variables declared in their,
signature, C<< $self >>, C<< $class >>, C<< @_ >>, and globals.
They cannot access private attributes unless those private attributes
have public accessors.

=head3 Anonymous Methods

It I<is> possible to use C<method> without a name to return an
anonymous method (coderef):

  use Zydeco prefix => 'MyApp';
  
  class MyClass {
    method get_method ($foo) {
      method ($bar) {
        return $foo . $bar;
      }
    }
  }
  
  my $obj   = MyApp->new_myclass;
  my $anon  = $obj->get_method("FOO");
  say ref($anon);                       # CODE
  say $obj->$anon("BAR");               # FOOBAR

Note that while C<< $anon >> is a coderef, it is still a method, and
still expects to be passed an object as C<< $self >>.

Due to limitations with L<Keyword::Simple>, keywords are always
complete statements, so C<< method ... >> has an implicit semicolon
before and after it. This means that this won't work:

  my $x = method { ... };

Because it gets treated as:

  my $x = ;
  method { ... };

A workaround is to wrap it in a C<< do { ... } >> block.

  my $x = do { method { ... } };

=head3 Private methods

A shortcut for the pattern of:

  my $x = do { method { ... } };

Is this:

  method $x { ... }

Zydeco will declare the variable C<< my $x >> for you, assign the
coderef to the variable, and you don't need to worry about a C<do> block
to wrap it.

=head3 Multimethods

Multi methods should I<< Just Work [tm] >> if you prefix them with the
keyword C<multi>

  use Zydeco prefix => 'MyApp';
  
  class Widget {
    multi method foo :alias(quux) (Any $x) {
      say "Buzz";
    }
    multi method foo (HashRef $h) {
      say "Fizz";
    }
  }
  
  my $thing = MyApp->new_widget;
  $thing->foo( {} );       # Fizz
  $thing->foo( 42 );       # Buzz
  
  $thing->quux( {} );      # Buzz

Outside of C<class>, C<abstract class>, C<role>, and C<interface> blocks,
C<multi method> will define a multi method in the caller package. (That is,
usually the factory.)

Multimethods cannot be anonymous or private.

=head2 C<< requires >>

Indicates that a role requires classes to fulfil certain methods.

  role Payable {
    requires account;
    requires deposit (Num $amount);
  }
  
  class Employee {
    extends Person;
    with Payable;
    has account!;
    method deposit (Num $amount) {
      ...;
    }
  }

Required methods have an optional signature; this is usually ignored, but
if L<Devel::StrictMode> determines that strict behaviour is being used,
the signature will be applied to the method via an C<around> modifier.

Or to put it another way, this:

  role Payable {
    requires account;
    requires deposit (Num $amount);
  }

Is a shorthand for this:

  role Payable {
    requires account;
    requires deposit;
    
    use Devel::StrictMode 'STRICT';
    if (STRICT) {
     around deposit (Num $amount) {
       $self->$next(@_);
     }
    }
  }

Can only be used in C<role> and C<interface> blocks.

=head2 C<< before >>

  before marry {
    say "Speak now or forever hold your peace!";
  }

As with C<method>, C<< $self >> and C<< $class >> are defined.

As with C<method>, you can provide a signature:

  before marry ( Person $partner, Object $date? ) {
    say "Speak now or forever hold your peace!";
  }

Note that this will result in the argument types being checked/coerced twice;
once by the before method modifier and once by the method itself. Sometimes
this may be desirable, but at other times your before method modifier might
not care about the types of the arguments, so can omit checking them.

  before marry ( $partner, $date? ) {
    say "Speak now or forever hold your peace!";
  }

Commas may be used to modify multiple methods:

  before marry, sky_dive (@args) {
    say "wish me luck!";
  }

The C<< :optimize >> attribute is supported for C<before>.

Method modifiers do work outside of C<class>, C<abstract class>, C<role>,
and C<interface> blocks, modifying methods in the caller package, which is
usually the factory package.

=head2 C<< after >>

There's not much to say about C<after>. It's just like C<before>.

  after marry {
    say "You may kiss the bride!";
  }
  
  after marry ( Person $partner, Object $date? ) {
    say "You may kiss the bride!";
  }
  
  after marry ( $partner, $date? ) {
    say "You may kiss the bride!";
  }

Commas may be used to modify multiple methods:

  after marry, finished_school_year (@args) {
    $self->go_on_holiday();
  }

The C<< :optimize >> attribute is supported for C<after>.

Method modifiers do work outside of C<class>, C<abstract class>, C<role>,
and C<interface> blocks, modifying methods in the caller package, which is
usually the factory package.

=head2 C<< around >>

The C<around> method modifier is somewhat more interesting.

  around marry ( Person $partner, Object $date? ) {
    say "Speak now or forever hold your peace!";
    my $return = $self->$next(@_);
    say "You may kiss the bride!";
    return $return;
  }

The C<< $next >> variable holds a coderef pointing to the "original" method
that is being modified. This gives your method modifier the ability to munge
the arguments seen by the "original" method, and munge any return values.
(I say "original" in quote marks because it may not really be the original
method but another wrapper!)

C<< $next >> and C<< $self >> are both shifted off C<< @_ >>.

If you use the signature-free version then C<< $next >> and C<< $self >>
are not shifted off C<< @_ >> for you, but the variables are still defined.

  around marry {
    say "Speak now or forever hold your peace!";
    my $return = $self->$next($_[2], $_[3]);
    say "You may kiss the bride!";
    return $return;
  }

Commas may be used to modify multiple methods:

  around insert, update ($dbh, @args) {
    $dbh->begin_transaction;
    my $return = $self->$next(@_);
    $dbh->commit_transaction;
    return $return;
  }

The C<< :optimize >> attribute is supported for C<around>.

Note that C<< SUPER:: >> won't work as expected in Zydeco, so
C<around> should be used instead.

Method modifiers do work outside of C<class>, C<abstract class>, C<role>,
and C<interface> blocks, modifying methods in the caller package, which is
usually the factory package.

=head2 C<< factory >>

The C<factory> keyword is used to define alternative constructors for
your class.

  class Person {
    has name   ( type => Str, required => true );
    has gender ( type => Str );
    
    factory new_man (Str $name) {
      return $class->new(name => $name, gender => 'male');
    }
    
    factory new_woman (Str $name) {
      return $class->new(name => $name, gender => 'female');
    }
  }

But here's the twist. These methods are defined within the factory
package, not within the class.

So you can call:

  MyApp->new_man("Bob")             # yes

But not:

  MyApp::Person->new_man("Bob")     # no

Note that if your class defines I<any> factory methods like this, then the
default factory method (in this case C<< MyApp->new_person >> will no longer
be automatically created. But you can create the default one easily:

  class Person {
    has name   ( type => Str, required => true );
    has gender ( type => Str );
    
    factory new_man (Str $name) { ... }
    factory new_woman (Str $name) { ... }
    factory new_person;   # no method signature or body!
  }

Within a factory method body, the variable C<< $class >> is defined, just
like normal methods, but C<< $self >> is not defined. There is also a
variable C<< $factory >> which is a string containing the factory
package name. This is because you sometimes need to create more than
just one object in a factory method.

  class Wheel;
  
  class Car {
    has wheels = [];
    
    factory new_three_wheeler () {
      return $class->new(
        wheels => [
          $factory->new_wheel,
          $factory->new_wheel,
          $factory->new_wheel,
        ]
      );
    }
    
    factory new_four_wheeler () {
      return $class->new(
        wheels => [
          $factory->new_wheel,
          $factory->new_wheel,
          $factory->new_wheel,
          $factory->new_wheel,
        ]
      );
    }
  }

As with C<method> and the method modifiers, if you provide a signature,
C<< $factory >> and C<< $class >> will be shifted off C<< @_ >>. If you
don't provide a signature, the variables will be defined, but not shifted
off C<< @_ >>.

An alternative way to provide additional constructors is with C<method>
and then use C<factory> to proxy them.

  class Person {
    has name   ( type => Str, required => true );
    has gender ( type => Str );
    
    method new_guy (Str $name) { ... }
    method new_gal (Str $name) { ... }
    
    factory new_person;
    factory new_man via new_guy;
    factory new_woman via new_gal;
  }

Now C<< MyApp->new_man >> will call C<< MyApp::Person->new_guy >>.

C<< factory new_person >> with no C<via> or method body is basically
like saying C<< via new >>.

The C<< :optimize >> attribute is supported for C<factory>.

The C<factory> keyword can only be used inside C<class> blocks.

=head3 Implementing a singleton

Factories make it pretty easy to implement the singleton pattern.

  class AppConfig {
    ...;
    
    factory get_appconfig () {
      state $config = $class->new();
    }
  }

Now C<< MyApp->get_appconfig >> will always return the same AppConfig object.
Because any explicit use of the C<factory> keyword in a class definition
suppresses the automatic creation of a factory method for the class, there
will be no C<< MyApp->new_appconfig >> method for creating new objects
of that class.

(People can still manually call C<< MyApp::AppConfig->new >> to get a new
AppConfig object, but remember Zydeco discourages calling constructors
directly, and encourages you to use the factory package for instantiating
objects!)

=head2 C<< type_name >>

  class Homo::Sapiens {
    type_name Human;
  }

The class will still be called L<MyApp::Homo::Sapiens> but the type in the
type library will be called B<Human> instead of B<Homo_Sapiens>.

Can only be used in C<class>, C<abstract class>, C<role>, and C<interface>
blocks.

=head2 C<< coerce >>

  class Person {
    has name   ( type => Str, required => true );
    has gender ( type => Str );
    
    coerce from Str via from_string {
      $class->new(name => $_);
    }
  }
  
  class Company {
    has owner ( type => 'Person', required => true );
  }
  
  my $acme = MyApp->new_company( owner => "Bob" );

Note that the company owner is supposed to be a person object, not a string,
but the Person class knows how create a person object from a string.

Coercions are automatically enabled in a lot of places for types that have
a coercion. For example, types in signatures, and types in attribute
definitions.

Note that the coercion body doesn't allow signatures, and the value being
coerced will be found in C<< $_ >>. If you want to have signatures, you
can define a coercion as a normal method first:

  class Person {
    has name   ( type => Str, required => true );
    has gender ( type => Str );
    
    method from_string ( Str $name ) {
      $class->new(name => $name);
    }
    
    coerce from Str via from_string;
  }

In both cases, a C<< MyApp::Person->from_string >> method is generated
which can be called to manually coerce a string into a person object.

They keyword C<< from >> is technically optional, but does make the
statement more readable.

  coerce Str via from_string {      # this works
    $class->new(name => $_);
  }

The C<< :optimize >> attribute is not currently supported for C<coerce>.

Can only be used in C<class> blocks.

=head2 C<< overload >>

  class Collection {
    has items = [];
    overload '@{}' => sub { shift->list };
  }

The list passed to C<overload> is passed to L<overload> with no other
processing.

Can only be used in C<class> blocks.

=head2 C<< version >>

  class Person {
    version 1.0;
  }

This just sets C<< $MyApp::Person::VERSION >>.

Can only be used in C<class>, C<abstract class>, C<role>, and C<interface>
blocks.

You can set a default version for all packages like this:

  use Zydeco (
    ...,
    version => 1.0,
  );

If C<class> definitions are nested, C<version> will be inherited by
child classes. If a parent class is specified via C<extends>, C<version>
will not be inherited.

=head2 C<< authority >>

  class Person {
    authority 'cpan:TOBYINK';
  }

This just sets C<< $MyApp::Person::AUTHORITY >>.

It is used to indicate who is the maintainer of the package.

Can only be used in C<class>, C<abstract class>, C<role>, and C<interface>
blocks.

  use Zydeco (
    ...,
    version   => 1.0,
    authority => 'cpan:TOBYINK',
  );

If C<class> definitions are nested, C<authority> will be inherited by
child classes. If a parent class is specified via C<extends>, C<authority>
will not be inherited.

=head2 C<< include >>

C<include> is the Zydeco equivalent of Perl's C<require>.

  package MyApp {
    use Zydeco;
    include Database;
    include Classes;
    include Roles;
  }

It works somewhat more crudely than C<require> and C<use>, evaluating
the included file pretty much as if it had been copy and pasted into the
file that included it.

The names of the files to load are processsed using the same rules for
prefixes as classes and roles (so MyApp::Database, etc in the example),
and C<< @INC >> is searched just like C<require> and C<use> do, but
instead of looking for a file called "MyApp/Database.pm", Zydeco
will look for "MyApp/Database.pl" (yes, ".pl"). This naming convention
ensures people won't accidentally load MyApp::Database using C<use>
or C<require> because it isn't intended to be loaded outside the context
of the MyApp package.

The file "MyApp/Database.pl" might look something like this:

  class Database {
    has dbh = DBI->connect(...);
    
    factory get_db {
      state $instance = $class->new;
    }
  }

Note that it doesn't start with a C<package> statement, nor
C<use Zydeco>. It's just straight on to the definitions.
There's no C<< 1; >> needed at the end.

C<< use strict >> and C<< use warnings >> are safe to put in the
file if you need them to satisfy linters, but they're not necessary
because the contents of the file are evaluated as if they had been
copied and pasted into the main MyApp module.

There are I<no> checks to prevent a file from being included more than
once, and there are I<no> checks to deal with cyclical inclusions.

Inclusions are currently only supported at the top level, and not within
class and role definitions.

=head2 C<< Zydeco::PACKAGE_SPEC() >>

This function can be used while a class or role is being compiled to
tweak the specification for the class/role.

  class Foo {
    has foo;
    Zydeco::PACKAGE_SPEC->{has}{foo}{type} = Int;
  }

It returns a hashref of attributes, methods, etc. L<MooX::Press> should
give you an idea about how the hashref is structured, but Zydeco only
supports a subset of what MooX::Press supports. For example, MooX::Press
allows C<has> to be an arrayref or a hashref, but Zydeco only supports
a hashref. The exact subset that Zydeco supports is subject to change
without notice.

This can be used to access MooX::Press features that Zydeco doesn't
expose.

=head2 IMPORTS

Zydeco also exports constants C<true> and C<false> into your
namespace. These show clearer boolean intent in code than using 1 and 0.

Zydeco exports C<rw>, C<ro>, C<rwp>, C<lazy>, C<bare>, and C<private>
constants which make your attribute specs a little cleaner looking.

Zydeco exports C<blessed> from L<Scalar::Util> because that can be
handy to have, and C<confess> from L<Carp>. Zydeco's copy of C<confess>
is super-powered and runs its arguments through C<sprintf>.

  before vote {
    if ($self->age < 18) {
      confess("Can't vote, only %d", $self->age);
    }
  }

Zydeco turns on strict, warnings, and the following modern Perl
features:

  # Perl 5.14 and Perl 5.16
  say state unicode_strings
  
  # Perl 5.18 or above
  say state unicode_strings unicode_eval evalbytes current_sub fc

If you're wondering why not other features, it's because I didn't want to
enable any that are currently classed as experimental, nor any that require
a version of Perl above 5.18. The C<switch> feature is mostly seen as a
failed experiment these days, and C<lexical_subs> cannot be called as methods
so are less useful in object-oriented code.

You can, of course, turn on extra features yourself.

  package MyApp {
    use Zydeco;
    use feature qw( lexical_subs postderef );
    
    ...;
  }

(The C<current_sub> feature is unlikely to work fully unless you
have C<:optimize> switched on for that method, or the method does not
include a signature. For non-optimized methods with a signature, a
wrapper is installed that handles checks, coercions, and defaults.
C<< __SUB__ >> will point to the "inner" sub, minus the wrapper.)

Zydeco exports L<Syntax::Keyword::Try> for you. Useful to have.

And last but not least, it exports all the types, C<< is_* >> functions,
and C<< assert_* >> functions from L<Types::Standard>,
L<Types::Common::String>, and L<Types::Common::Numeric>.

You can choose which parts of Zydeco you import:

  package MyApp {
    use Zydeco keywords => [qw/
      -booleans
      -privacy
      -utils
      -types
      -is
      -assert
      -features
      try
      class abstract role interface
      include toolkit begin end extends with requires
      has constant method multi factory before after around
      type_name coerce
      version authority overload
    /];

It should mostly be obvious what they all do, but C<< -privacy >> is
C<ro>, C<rw>, C<rwp>, etc; C<< -types >> is bareword type constraints
(though even without this export, they should work in method signatures),
C<< -is >> are the functions like C<is_NonEmptyStr> and C<is_Object>,
C<< -assert >> are functions like C<assert_Int>, C<< -utils >> gives
you C<blessed> and C<confess>.

=head1 FEATURES

=head2 Helper Subs

Earlier it was stated that C<sub> cannot be used to define methods in
classes and roles. This is true, but that doesn't mean that it has no
use.

  package MyApp {
    use Zydeco;
    
    sub helper_function { ... }
    
    class Foo {
      method foo {
        ...;
        helper_function(...);
        ...;
      }
    }
    
    class Bar {
      sub other_helper { ... }
      method bar {
        ...;
        helper_function(...);
        other_helper(...);
        ...;
      }
    }
  }

The subs defined by C<sub> end up in the "MyApp" package, not
"MyApp::Foo" or "MyApp::Bar". They can be called by any of the classes
and roles defined in MyApp. This makes them suitable for helper subs
like logging, L<List::Util>/L<Scalar::Util> sorts of functions, and
so on.

  package MyApp {
    use Zydeco;
    
    use List::Util qw( any all first reduce );
    # the above functions are now available within
    # all of MyApp's classes and roles, but won't
    # pollute any of their namespaces.
    
    use namespace::clean;
    # And now they won't even pollute MyApp's namespace.
    # Though I'm pretty sure this will also stop them
    # from working in any methods that used ":optimize".
    
    class Foo { ... } 
    role Bar { ... } 
    role Baz { ... } 
  }

C<sub> is also usually your best option for those tiny little
coderefs that need to be defined here and there:

  has foo (
    is       => lazy,
    type     => ArrayRef[Str],
    builder  => sub {  []  },
  );

Though consider using L<Sub::Quote> if you're using Moo.

=head2 Anonymous Classes and Roles

=head3 Anonymous classes

It is possible to make anonymous classes:

  my $class  = do { class; };
  my $object = $class->new;

The C<< do { ... } >> block is necessary because of a limitation in
L<Keyword::Simple>, where any keywords it defines must be complete
statements.

Anonymous classes can have methods and attributes and so on:

  my $class = do { class {
    has foo (type => Int);
    has bar (type => Int);
  }};
  
  my $object = $class->new(foo => 1, bar => 2);

Anonymous classes I<do not> implicitly inherit from their parent like
named nested classes do. Named classes nested inside anonymous classes
I<do not> implicitly inherit from the anonymous class.

Having one anonymous class inherit from another can be done though:

  my $base     = do { class; }
  my $derived  = do { class {
    extends {"::$k1"};
  }};

This works because C<extends> accepts a block which returns a string for
the package name, and the string needs to begin with "::" to avoid the
auto prefix mechanism.

=head3 Anonymous roles

Anonymous roles work in much the same way.

=head2 Parameterizable Classes and Roles

=head3 Parameterizable classes

  package MyApp {
    use Zydeco;
    
    class Animal {
      has name;
    }
    
    class Species ( Str $common_name, Str $binomial ) {
      extends Animal;
      constant common_name  = $common_name;
      constant binomial     = $binomial;
    }
    
    class Dog {
      extends Species('dog', 'Canis familiaris');
      method bark () {
        say "woof!";
      }
    }
  }

Here, "MyApp::Species" isn't a class in the usual sense; you cannot create
instances of it. It's like a template for generating classes. Then 
"MyApp::Dog" generates a class from the template and inherits from that.

  my $Cat = MyApp->generate_species('cat', 'Felis catus');
  my $mog = $Cat->new(name => 'Mog');
  
  $mog->isa('MyApp::Animal');         # true
  $mog->isa('MyApp::Species');        # false!!!
  $mog->isa($Cat);                    # true

Because there are never any instances of "MyApp::Species", it doesn't
make sense to have a B<Species> type constraint. Instead there are
B<SpeciesClass> and B<SpeciesInstance> type constraints.

  use MyApp::Types -is;
  
  my $lassie = MyApp->new_dog;
  
  is_Animal( $lassie );               # true
  is_Dog( $lassie );                  # true
  is_SpeciesInstance( $lassie );      # true
  is_SpeciesClass( ref($lassie) );    # true

Subclasses cannot be nested inside parameterizable classes, but
parameterizable classes can be nested inside regular classes, in
which case the classes they generate will inherit from the outer
class.

  package MyApp {
    use Zydeco;
    
    class Animal {
      has name;
      class Species ( Str $common_name, Str $binomial ) {
        constant common_name  = $common_name;
        constant binomial     = $binomial;
      }
    }
    
    class Dog {
      extends Species('dog', 'Canis familiaris');
      method bark () {
        say "woof!";
      }
    }
  }

Anonymous parameterizable classes are possible:

  my $generator = do { class ($footype, $bartype) {
    has foo (type => $footype);
    has bar (type => $bartype);
  } };
  
  my $class = $generator->generate_package(Int, Num);
  
  my $object = $class->new(foo => 42, bar => 4.2);

=head3 Parameterizable roles

Often it makes more sense to parameterize roles than classes.

  package MyApp {
    use Zydeco;
    
    class Animal {
      has name;
    }
    
    role Species ( Str $common_name, Str $binomial ) {
      constant common_name  = $common_name;
      constant binomial     = $binomial;
    }
    
    class Dog {
      extends Animal;
      with Species('dog', 'Canis familiaris'), GoodBoi?;
      method bark () {
        say "woof!";
      }
    }
  }

Anonymous parameterizable roles are possible.

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Zydeco>.

=head1 TODO

=head2 Plugin system

Zydeco can often load MooX/MouseX/MooseX plugins and work
fine with them, but some things won't work, like plugins that rely on
being able to wrap C<has>. So it would be nice to have a plugin system
that extensions can hook into.

If you're interested in extending Zydeco, file a bug report about
it and let's have a conversation about the best way for that to happen.
I probably won't start a plugin API until someone actually wants to
write a plugin, because that will give me a better idea about what kind
of API is required.

=head1 SEE ALSO

Less magic version:
L<MooX::Press>.

Important underlying technologies:
L<Moo>, L<Type::Tiny::Manual>, L<Sub::HandlesVia>, L<Sub::MultiMethod>,
L<Lexical::Accessor>, L<Syntax::Keyword::Try>.

Similar modules:
L<Moops>, L<Kavorka>, L<Dios>, L<MooseX::Declare>.

=head2 Zydeco vs Moops

Because I also wrote Moops, people are likely to wonder what the difference
is, and why re-invent the wheel?

Zydeco has fewer dependencies than Moops, and crucially doesn't rely on
L<Package::Keyword> and L<Devel::CallParser> which have... issues.
Zydeco uses Damian Conway's excellent L<PPR> to handle most parsing
needs, so parsing should be more predictable.

Moops is faster in most circumstances though.

Here are a few key syntax and feature differences.

=head3 Declaring a class

Moops:

  class Foo::Bar 1.0 extends Foo with Bar {
    ...;
  }

Zydeco:

  class Foo::Bar {
    version 1.0;
    extends Foo;
    with Bar;
  }

Moops and Zydeco use different logic for determining whether a class
name is "absolute" or "relative". In Moops, classes containing a "::" are seen
as absolute class names; in Zydeco, only classes I<starting with> "::"
are taken to be absolute; all others are given the prefix.

Moops:

  package MyApp {
    use Moops;
    class Foo {
      class Bar {
        class Baz {
          # Nesting class blocks establishes a naming
          # heirarchy so this is MyApp::Foo::Bar::Baz!
        }
      }
    }
  }

Zydeco:

  package MyApp {
    use Zydeco;
    class Foo {
      class Bar {
        class Baz {
          # This is only MyApp::Baz, but nesting
          # establishes an @ISA chain instead.
        }
      }
    }
  }

=head3 How namespacing works

Moops:

  use feature 'say';
  package MyApp {
    use Moops;
    use List::Util qw(uniq);
    class Foo {
      say __PACKAGE__;         # MyApp::Foo
      say for uniq(1,2,1,3);   # ERROR!
      sub foo { ... }          # MyApp::Foo::foo()
    }
  }

Zydeco:

  use feature 'say';
  package MyApp {
    use Zydeco;
    use List::Util qw(uniq);
    class Foo {
      say __PACKAGE__;         # MyApp
      say for uniq(1,2,1,3);   # this works fine
      sub foo { ... }          # MyApp::foo()
    }
  }

This is why you can't use C<sub> to define methods in Zydeco.
You need to use the C<method> keyword. In Zydeco, all the code
in the class definition block is still executing in the parent
package's namespace!

=head3 Multimethods

Moops/Kavorka multimethods are faster, but Zydeco is smarter at
picking the best candidate to dispatch to, and intelligently selecting
candidates across inheritance hierarchies and role compositions.

=head3 Other crazy Kavorka features

Kavorka allows you to mark certain parameters as read-only or aliases,
allows you to specify multiple names for named parameters, allows you
to rename the invocant, allows you to give methods and parameters
attributes, allows you to specify a method's return type, etc, etc.

Zydeco's C<method> keyword is unlikely to ever offer as many
features as that. It is unlikely to offer many more features than it
currently offers.

If you need fine-grained control over how C<< @_ >> is handled, just
don't use a signature and unpack C<< @_ >> inside your method body
however you need to.

=head3 Lexical accessors

Zydeco has tighter integration with L<Lexical::Accessor>,
allowing you to use the same keyword C<has> to declare private
and public attributes.

=head3 Factories

Zydeco puts an emphasis on having a factory package for instantiating
objects. Moops didn't have anything similar.

=head3 C<augment> and C<override>

These are L<Moose> method modifiers that are not implemented by L<Moo>.
Moops allows you to use these in Moose and Mouse classes, but not Moo
classes. Zydeco simply doesn't support them.

=head3 Type Libraries

Moops allowed you to declare multiple type libraries, define type
constraints in each, and specify for each class and role which type
libraries you want it to use.

Zydeco automatically creates a single type library for all
your classes and roles within a module to use, and automatically
populates it with the types it thinks you might want.

If you need to use other type constraints:

  package MyApp {
    use Zydeco;
    # Just import types into the factory package!
    use Types::Path::Tiny qw( Path );
    
    class DataSource {
      has file => ( type => Path );
      
      method set_file ( Path $file ) {
        $self->file( $file );
      }
    }
  }
  
  my $ds = MyApp->new_datasource;
  $ds->set_file('blah.txt');      # coerce Str to Path
  print $ds->file->slurp_utf8;

=head3 Constants

Moops:

  class Foo {
    define PI = 3.2;
  }

Zydeco:

  class Foo {
    constant PI = 3.2;
  }

=head3 Parameterizable classes and roles

These were always on my todo list for Moops; I doubt they'll ever be done.
They work nicely in Zydeco though.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2020 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

