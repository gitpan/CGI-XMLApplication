# $Id: XMLApplication.pm,v 1.9 2001/12/10 23:12:13 cb13108 Exp $

package CGI::XMLApplication;

# ################################################################
# $Revision: 1.9 $
# $Author: cb13108 $
#
# (c) 2001 Christian Glahn <christian.glahn@uibk.ac.at>
# All rights reserved.
#
# This code is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# ################################################################

##
# CGI::XMLApplication - Application Module for CGI scripts

# ################################################################
# module loading and global variable initializing
# ################################################################
use strict;

use CGI;
use Carp;

# ################################################################
# inheritance
# ################################################################
@CGI::XMLApplication::ISA = qw( CGI );

# ################################################################

$CGI::XMLApplication::VERSION = "1.1.0";

# ################################################################
# general configuration
# ################################################################

# some hardcoded error messages, the application has always, e.g.
# to tell that a stylesheet is missing
@CGI::XMLApplication::panic = (
          'No Stylesheet specified! ',
          'Stylesheet is not available! ',
          'Event not defined',
          'Application Error',
         );

# The Debug Level for verbose error messages
$CGI::XMLApplication::DEBUG = 0;

# ################################################################
# methods
# ################################################################
sub new {
    my $class = shift;
    my $self = $class->SUPER::new( @_ );
    bless $self, $class;

    $self->{XML_CGIAPP_HANDLER_}    = [$self->registerEvents()];
    $self->{XML_CGIAPP_STYLESHEET_} = [];
    $self->{XML_CGIAPP_STYLESDIR_}  = '';

    return $self;
}

# ################################################################
# straight forward coded methods

# application related ############################################
# both functions are only for backward compatibilty with older scripts
sub debug_msg {
    my $level = shift;
    if ( $level <= $CGI::XMLApplication::DEBUG && scalar @_ ) {
        my ($module, undef, $line) = caller(1);
        warn "[$module; line: $line] ", join(' ', @_) , "\n";
    }
}

##
# dummy functions
#
# each function is required to be overwritten by any class inheritated
sub registerEvents   { return (); }

# all following function will recieve the context, too
sub getDOM           { return undef; }
sub requestDOM       { return undef; }  # old style use getDOM!

sub getStylesheetString { return ""; }     # return a XSL String
sub getStylesheet       { return ""; }     # returns either name of a stylesheetfile or the xsl DOM
sub selectStylesheet    { return ""; }     # old style getStylesheet

sub getXSLParameter  { return (); }  # should return a plain hash of parameters passed to xsl
sub setHttpHeader    { return (); }  # should return a hash of header

sub skipSerialization{
    my $self = shift;
    $self->{CGI_XMLAPP_SKIP_TRANSFORM} = shift if scalar @_;
    return $self->{CGI_XMLAPP_SKIP_TRANSFORM};
}

# returns boolean
sub passthru {
    my $self = shift;
    if ( scalar @_ ) {
        $self->{CGI_XMLAPP_PASSXML} = shift;
        $self->delete( 'passthru' ); # delete any passthru parameter
    }
    elsif ( defined $self->param( "passthru" ) ) {
        $self->{CGI_XMLAPP_PASSXML} = 1    ;
        $self->delete( 'passthru' );
    }
    return $self->{CGI_XMLAPP_PASSXML};
}

sub redirectToURI {
    my $self = shift;
    $self->{CGI_XMLAPP_REDIRECT} = shift if scalar @_;
    return $self->{CGI_XMLAPP_REDIRECT};
}

# ################################################################
# content related functions

# stylesheet directory information ###############################
sub setStylesheetDir  { $_[0]->{XML_CGIAPP_STYLESDIR_} = $_[1];}
sub setStylesheetPath { $_[0]->{XML_CGIAPP_STYLESDIR_} = $_[1];}
sub getStylesheetDir  { $_[0]->{XML_CGIAPP_STYLESDIR_}; }
sub getStylesheetPath { $_[0]->{XML_CGIAPP_STYLESDIR_}; }

# event control ###################################################
sub addEvent          { my $s=shift; push @{$s->{XML_CGIAPP_HANDLER_}}, @_;}
sub getEventList      { @{ $_[0]->{XML_CGIAPP_HANDLER_} }; }

sub testEvent         { return $_[0]->checkPush( $_[0]->getEventList() ); }

sub deleteEvent       {
    my $self = shift;
    if ( scalar @_ ){
        foreach ( @_ ) {
            debug_msg( 8, "[XML::CGIAppliction] delete event $_" );
            $self->delete( $_ );
            $self->delete( $_.'.x' );
            $self->delete( $_.'.y' );
        }
    }
    else {
        foreach ( @{ $self->{XML_CGIAPP_HANDLER_} } ){
            debug_msg( 8, "delete event $_" );
            $self->delete( $_ );
            $self->delete( $_.'.x' );
            $self->delete( $_.'.y' );
        }
    }
}

sub sendEvent         {
    debug_msg( 10, "send event " . $_[1] );
    $_[0]->deleteEvent();
    $_[0]->param( -name=>$_[1] , -value=>1 );
}

# error handling #################################################
sub setPanicMsg       { $_[0]->{XML_CGIAPP_PANIC_} = $_[1] }
sub getPanicMsg       { $_[0]->{XML_CGIAPP_PANIC_} }

# ################################################################
# predefined events

# default event handler prototypes
sub event_init    {}
sub event_exit    {}
sub event_default { return 0 }

# ################################################################
# CGI specific helper functions

# this is required by the eventhandling
sub checkPush {
    my $self = shift;
    my ( $pushed ) = grep {
        length $self->param( $_ ) ||  length $self->param( $_.'.x')
    } @_;
    $pushed =~ s/\.x$//i if defined $pushed;
    return $pushed;
}

# helper functions which were missing in CGI.pm
sub checkFields{
    my $self = shift;
    my @missing = grep {
        not length $self->param( $_ ) || $self->param( $_ ) =~ /^\s*$/
    } @_;
    return wantarray ? @missing : ( scalar(@missing) > 0 ? undef : 1 );
}

sub getParamHash {
    my $self = shift;
    my $ptrHash = $self->Vars;
    my $ptrRV   = {};

    foreach my $k ( keys( %{$ptrHash} ) ){
        next unless exists $ptrHash->{$_} && $ptrHash->{$_} !~ /^[\s\0]*$/;
        $ptrRV->{$k} = $ptrHash->{$k};
    }

    return wantarray ? %{$ptrRV} : $ptrRV;
}

# ################################################################
# application related methods
# ################################################################
# algorithm should be
# event registration
# app init
# event handling
# app exit
# serialization and output
# error handling
sub run {
    my $self = shift;
    my $sid = -1;
    my $ctxt = {@_}; # context hash

    $self->event_init($ctxt);

    if ( my $n = $self->checkPush( $self->getEventList() ) ) {
        if ( my $func = $self->can( 'event_'.$n ) ) {
            $sid = $self->$func($ctxt)
        }
        else {
            $sid = -3;
        }
    }

    if ( $sid == -1 ){
        $sid = $self->event_default($ctxt);
    }

    $self->event_exit($ctxt);

    # if we allready panic, don't try to render
    if ( $sid >= 0 ) {
        # check if we wanna redirect
        if ( my $uri = $self->redirectToURI() ) {
            my %h = $self->setHttpHeader( $ctxt );
            print $self->header( %h );
            print $self->redirect( -uri=>$uri ) . "\n\n";
        }
        elsif ( not $self->skipSerialization() ) {
            # sometimes it is nessecary to skip the serialization
            # eg. due passing binary data.
            $sid = $self->serialization( $ctxt );
        }
    }

    $self->panic( $sid, $ctxt );
}

sub serialization {
    # i require both modules here, so one can implement his own
    # serialization
    require XML::LibXML;
    require XML::LibXSLT;

    my $self = shift;
    my $ctxt = shift;
    my $id;

    my %header = $self->setHttpHeader( $ctxt );

    my $xml_doc = $self->getDOM( $ctxt );
    if ( not defined $xml_doc ) {
        debug_msg( 10, "use old style interface");
        $xml_doc = $self->requestDOM( $ctxt );
    }
    # if still no document is available
    if ( not defined $xml_doc ) {
        debug_msg( 10, "no DOM defined; use empty DOM" );
        $xml_doc = XML::LibXML::Document->new;
        # the following line is to keep xpath.c quiet!
        $xml_doc->setDocumentElement( $xml_doc->createElement( "dummy" ) );
    }

    if( defined $self->passthru() && $self->passthru() == 1 ) {
        # this is a useful feature for DOM debugging
        debug_msg( 10, "attempt to pass the DOM to the client" );
        $header{-type} = 'text/xml';
        print $self->header( %header  );
        print $xml_doc->toString();
        return 0;
    }

    my $stylesheet = $self->getStylesheet( $ctxt );

    my ( $xsl_dom, $style, $res );
    my $parser = XML::LibXML->new();
    my $xslt   = XML::LibXSLT->new();

    if ( ref( $stylesheet ) ) {
        debug_msg( 5, "stylesheet is reference"  );
        $xsl_dom = $stylesheet;
    }
    elsif ( -f $stylesheet && -r $stylesheet ) {
        debug_msg( 5, "filename is $stylesheet" );
        eval {
            $xsl_dom  = $parser->parse_file( $stylesheet );
        };
        if ( $@ ) {
            debug_msg( 3, "Corrupted Stylesheet:\n broken XML\n". $@ );
            $self->setPanicMsg( "Corrupted document:\n broken XML\n". $@ );
            return -2;
        }
    }
    else {
        # first test the new style interface
        my $xslstring = $self->getStylesheetString( $ctxt );
        if ( length $xslstring ) {
            debug_msg( 5, "stylesheet is xml string"  );
            eval { $xsl_dom = $parser->parse_string( $xslstring ); };
            if ( $@ || not defined $xsl_dom ) {
                # the parse failed !!!
                debug_msg( 3, "Corrupted Stylesheet String:\n". $@ ."\n" );
                $self->setPanicMsg( "Corrupted Stylesheet String:\n". $@ );
                return -2;
            }
        }
        else {
            # now test old style interface
            debug_msg( 5, "old style interface to select the stylesheet"  );
            $stylesheet = $self->selectStylesheet( $ctxt );
            if ( ref( $stylesheet ) ) {
                debug_msg( 5, "stylesheet is reference"  );
                $xsl_dom = $stylesheet;
            }
            elsif ( -f $stylesheet && -r $stylesheet ) {
                debug_msg( 5, "filename is $stylesheet" );
                eval {
                    $xsl_dom  = $parser->parse_file( $stylesheet );
                };
                if ( $@ ) {
                    debug_msg( 3, "Corrupted Stylesheet:\n broken XML\n". $@ );
                    $self->setPanicMsg( "Corrupted document:\n broken XML\n". $@ );
                    return -2;
                }
            }
            else {
                debug_msg( 2 , "panic stylesheet file $stylesheet does not exist" );
                $self->setPanicMsg( "$stylesheet" );
                return length $stylesheet ? -2 : -1 ;
            }
        }
    }

    eval {
        $style = $xslt->parse_stylesheet( $xsl_dom );
        # $style = $xslt->parse_stylesheet_file( $file );
    };
    if( $@ ) {
        debug_msg( 3, "Corrupted Stylesheet:\n". $@ ."\n" );
        $self->setPanicMsg( "Corrupted Stylesheet:\n". $@ );
        return -2;
    }

    my %xslparam = $self->getXSLParameter( $ctxt );
    eval {
        # first do special xpath encoding of the parameter
        if ( %xslparam && scalar( keys %xslparam ) > 0 ) {
            $res = $style->transform( $xml_doc,
                                      XML::LibXSLT::xpath_to_string(%xslparam)
                                    );
        }
        else {
            $res = $style->transform( $xml_doc );
        }
    };
    if( $@ ) {
        debug_msg( 3, "Broken Transformation:\n". $@ ."\n" );
        $self->setPanicMsg( "Broken Transformation:\n". $@ );
        return -2;
    }

    # override content-type with the correct content-type
    # of the style (is this ok?)
    $header{-type}    = $style->media_type;
    $header{-charset} = $style->output_encoding;

    debug_msg( 10, "serialization do output" );
    # we want nice xhtml and since the output_string does not the
    # right job
    my $out_string= undef;

    debug_msg( 9, "serialization get output string" );
    eval {
        $out_string =  $style->output_string( $res );
    };
    debug_msg( 10, "serialization rendered output" );
    if ( $@ ) {
        debug_msg( 3, "Corrupted Output:\n", $@ , "\n" );
        $self->setPanicMsg( "Corrupted Output:\n". $@ );
        return -2;
    }
    else {
        # do the output
        print $self->header( %header );
        print $out_string;
        debug_msg( 10, "output printed" );
    }

    return 0;
}

sub panic {
    my ( $self, $pid ) = @_;
    return unless $pid < 0;
    $pid++;
    $pid*=-1;

    my $str = "Application Panic: ";
    $str = "PANIC $pid :" .  $CGI::XMLApplication::panic[$pid] ;
    # this is nice for debugging from logfiles...
    $str  = $self->b( $str ) . "<br />\n";
    $str .= $self->pre( $self->getPanicMsg() );
    $str .= "Please Contact the Systemadminstrator<br />\n";

    debug_msg( 1, "$str" );

    if ( $CGI::XMLApplication::Quiet == 1 ) {
        $str = "Application Panic";
    }
    if ( $CGI::XMLApplication::Quiet == 2 ) {
        $str = "";
    }

    my $status = $pid < 3 ? 404 : 500; # default is the application error ...
    print $self->header( -status => $status ) , $str ,"\n";

}

1;
# ################################################################
__END__

=head1 NAME

CGI::XMLApplication -- Object Oriented Interface for CGI Script Applications

=head1 SYNOPSIS

  use CGI::XMLApplication;

  $script = new CGI::XMLApplication;
  $script->setStylesheetPath( "the/path/to/the/stylesheets" );

  # either this for simple scripts
  $script->run();
  # or if you need more control ...
  $script->run(%context_hash);

=head1 DESCRIPTION

CGI::XMLApplication is a CGI application class, that intends to enable
perl artists to implement CGIs that make use of XML/XSLT
functionality, without taking too much care about specialized
errorchecking or even care too much about XML itself. It provides the
power of the L<XML::LibXML>/ L<XML::LibXSLT> module package for
content deliverment.

As well CGI::XMLApplication is designed to support project management
on code level. The class allows to split web applications into several
simple parts. Through this most of the code stays simple and easy to
maintain. Throughout the whole lifetime of a script
CGI::XMLApplication tries to keep the application stable. As well a
programmer has not to bother about some of XML::LibXML/ XML::LibXSLT
transformation pitfalls.

The class module extends the CGI class. While all functionality of the
original CGI package is still available, it should be not such a big
problem, to port existing scripts to CGI::XMLApplication, although
most functions used here are the access function for client data
such as I<param()>.

CGI::XMLApplication, intended to be an application class should make
writing of XML enabled CGI scripts more easy. Especially because of
the use of object orientated concepts, this class enables much more
transparent implemententations with complex functionality compared to
what is possible with standard CGI-scripts.

The main difference with common perl CGI implementation is the fact,
that the client-output is not done from perl functions, but generated
by an internally build XML DOM that gets processed with an XSLT
stylesheet. This fact helps to remove a lot of the HTML related
functions from the core code, so a script may be much easier to read,
since only application relevant code is visible, while layout related
information is left out (commonly in an XSLT file).

This helps to write and test a complete application faster and less
layout related. The design can be appended and customized later
without effecting the application code anymore.

Since the class uses the OO paradigma, it does not force anybody to
implement a real life application with the complete overhead of more
or less redundant code. Since most CGI-scripts are waiting for
B<events>, which is usually the abstraction of a click of a submit
button or an image, CGI::XMLApplication implements a simple event
system, that allows to keep event related code as separated as
possible.

Therefore final application class is not ment to have a constructor
anymore. All functionality should be encapsulated into implicit or
explicit event handlers. Because of a lack in Perl's OO implementation
the call of a superclass constructor before the current constructor
call is not default behavior in Perl. For that reason I decided to
have special B<events> to enable the application to initialize
correctly, excluding the danger of leaving important variables
undefined. On the other hand this forces the programmer to implement
scripts more problem orientated, rather than class focused.

Another design aspect for CGI::XMLApplication is the strict differentiation
between CODE and PRESENTATION. IMHO this, in fact being one of the
major problems in traditional CGI programming.  To implement this, the
XML::LibXML and XML::LibXSLT modules are used.  Each CGI Script should
generate an XML-DOM, that can be processed with a given stylesheet.

B<Pay attention that XML-DOM means the DOM of XML::LibXML and not XML::DOM!>

=head2 What are Events and how to catch them

Most CGI handle the result of HTML-Forms or similar requests from
clients.  Analouge to GUI Programming, CGI::XMLApplication calls this
an B<event>.  Spoken in CGI/HTML-Form words, a CGI-Script handles the
various situations a clients causes by pushing a submit button or
follows a special link.

An event of CGI::XMLApplication has the same B<name> as the input
field, that should cause the event. The following example should
illustrate this a little better:

    <!-- SOME HTML CODE -->
    <input type="submit" name="dummy" value="whatever" />
    <!-- SOME MORE HTML :) -->

If a user clicks the submitbutton and you have registered the event
name B<dummy> for your script, CGI::XMLApplication will try to call the
function B<event_dummy()>. The script module to handle the dummy event
would look something like the following code:

    use CGI::XMLApplication;
    @ISA = qw(CGI::XMLApplication);

    sub registerEvents { qw( dummy ); } # the handler list

    # ...

    sub event_dummy {
       my ( $self, $context ) = @_;

       # your event code goes here

       return 0;
    }

During the lifecircle of a CGI script, often the implementation starts
with ordinary submit buttons, which get often changed to so called
input images, to fit into the UI of the Website. CGI::XMLApplication
will recognize such changes, so the code has not to be changed if the
presentation of the form changes. Therefore there is no need to
declare separate events for input images. E.g. an event called evname
makes CGI::XMLApplication look for evname B<and> evname.x in the
querystring.

Some programmer are suspious which event CGI::XMLApplication will
call.  The function B<testEvent> checks all events if one is valid and
returns the name of event. Much more important is the possibility to
send B<error events> from the event_init() function. This is done with
the B<sendEvent> Function. This will set a new parameter to the CGI's
querystring after removing all other events. B<One can only send
events that are already registred!>.

CGI::XMLApplication doesn't implement an event queqe yet. For GUI
programmers this seems like a unnessecary restriction. I terms of CGI
it makes more sense to think of a script as a program, that is only
able to scan its event queqe only once during runtime. The only chance
to stop the script from handling a certain event is to send a new
event from the event_init() function. This function is always called
at first from the run method. If another event uses the sendEvent
function, the event will get lost.

=over 4

=item method run

Being the main routine this should be the only method called by the
script apart from the constructor. All events are handled inside the
method B<run()>.  Since this method is extremly simple and transparent
to any kind of display type, there should be no need to override this
function. One can pass a context hash, to pass external or prefetched
information to the application. This context will be available and
acessable in all events and most extra functions.

This function does all event and serialization related work. As well
there is some validation done as well, so catched events, that are not
implemented, will not cause any harm.

=back

=head2 The Event System

Commonly scripts that make use of CGI::XMLApplication, will not bother
about the B<run> function anymore. All functionality is kept inside
B<event>- and (pseudo-)B<callback functions>. This forces one to
implement much more strict code than common perl would allow. What
first looks like a drawback, finally makes the code much easier to
understand, maintain and finally to extend.

CGI::XMLApplication knows two types of event handlers: implicit
events, common to all applications and explicit events, reflecting the
application logic. The class assumes that implicit events are
implemented in any case. Those events have reserved names and need not
be specified through B<registerEvents>. Since the class cannot know
something about the application logic by itself, names of events have
to be explicitly passed to be handled by the application. As well all
event functions have to be implemented as member methods of the
application class right now. Because of perls OO interface a class has
to be written inside its own module.

An event may return a integer value. If the event succeeds (no fatal
errors, e.g. database errors) the explicit or common event function
should return a value greater or eqal than 0. If the value is less
than 0, CGI::XMLApplication assumes a script panic, and will not try
to render a stylesheet or DOM.

There are defined panic levels:

=over 4

=item -1

Stylesheet missing

=item -2

Stylesheet not available

=item -3

Event not defined

=item -4

Application panic

=back

Apart from B<Application Panic> the panic levels are set
internally. An Application Panic should be set if the application
catches an error, that does not allow any XML/XSLT processing. This
can be for example, that any required perl modules are not installed
on the system.

If the B<getStylesheet> is implemented the CGI::XMLApplication will
assume the returned value either as a filename of a stylesheet or as a
XML DOM representation of the same. If Stylesheets are stored in a
file accessable from the , one should set the common path for the
stylesheets and let B<CGI::XMLApplication> do the parsing job.

In cases the stylesheet is already present as a string (e.g. as a
result of a database query) one may pass this string directly to
B<CGI::XMLApplication>.

I<selectStylesheet> is an alias for I<getStylesheet> left for
compatibility reasons.

If none of these stylesheet selectors succeeds the I<Stylesheet
missing> panic code is thrown. If the parse of the XML fails
I<Stylesheet not available> is thrown. The latter case will also give
some informations where the stylesheet selection failed.

So how to tell the system about the available event handler?

There are two ways to tell the system which events are to be handled.

You can tell the system the events the client browser sends back to
the script only. CGI::XMLApplication tries to call a event handler if this
happens. The function name of an event handler has to have the
following format:

 event_<eventname>.

E.g. event_init handles the init event described below. All events
that handle client responses (including the default event) should
return the position of the stylesheet in the stylesheet list passed
with setStylesheetList().

=over 4

=item method registerEvents

This method is called by the class constructor. Each application
should register the events it like to handle. It should return an
array of eventnames such as eg. 'remove' or 'store'. This list is used
to find which event a user caused on the client side.

=item function testEvent

If it is nesseccary to check which event is relevant for the current
script one can use this function to find out in event_init(). If this
function returns undef, the default event is active, otherwise it
returns the eventname as defined by B<registerEvents>.

=item method addEvents LIST

addEvents() also takes a list of events the application will
handle. Contrary to setEventList() this does not override previously
defined events.

=item method sendEvent SCALAR

Sometimes it could be neccessary to send an event by your own (the
script's) initiative. A possible example could be if you don't have
client input but path_info data, which determinates how the script
should behave or session information is missing, so the client should
not even get the default output.

This can only be done during the event_init() method call. Some coders
would prefer the constructor, which is not a very good idea in this
case: While the constructor is running, the application is not
completely initialized. This fact can be only ashured in the
event_init function. Therefore all script specific errorhandling and
initializing should be done there.

B<sendEvent> only can be called from event_init, because any
CGI::XMLApplication script will handle just one event, plus the
B<init> and the B<exit event>. If B<sendEvent> is called from another
event than B<event_init()> it will take not effect.

It is possible through sendEvent() to keep the script logic clean.

Example:

  sub registerEvents { qw( missing ... ) ; }

  sub event_init {
     my ( $self, $context ) = @_;
     if ( not length $self->param( $paramname ) ){
        $self->sendEvent( 'missing' );
     }
     else {

    ... some more initialization ...

     }
  }

  ... more code ...

  # event_missing is an explicit event.
  sub event_missing {
     my ( $self , $context ) = @_;

     ... your error handling code goes ...

     return -4 if $panic;  # just for illustration
     return 0;
  }

=back

=head2 Implicit Events

CGI::XMLApplication knows three implicit events which are more or less
independent to client responses: They are 'init', 'exit', and
'default'.

If there is need to override one of these handler -- and I hope there
will be ;) -- the particular event should call the related event
handler of its superclass as first action. This might be skipped, if
the function should do everything right by itself.  I prefere the
first technique, because it is more secure and makes things easier to
debug.

Each event has a single Parameter, the context. This is a hash
reference, where the user can store whatever needed. This context is
usefull to pass scriptwide data between callbacks and event functions
around.

=over 4

=item event_init

The init event is set before the CGI::XMLApplication tries to evaluate
any of script parameters. Therefore the event_init method should be
used to initialize the application.

=item event_exit

The event_exit method is called after all other events have been
processed, but just before the rendering is done. This should be used,
if you need to do something independend from all events before the
data is send to the user.

=item event_default

This event is called as a fallback mechanism if CGI::XMLApplication
did not receive a stylesheet id by an other event handler; for example
if no event matched.

=back

=head2 Extra Methods

There are some extra callbacks may implemented:

=over 4

=item * selectStylesheet

=item * getDOM

=item * registerEvents

=item * setHttpHeader

=item * getXSLTParameter

=back

These methods are used by the serialization function, to create the
content related datastructure. Like event functions these functions
have to be implemented as class member, and like event funcitons the
functions will have the context passed as the single parameter.

B<selectStylesheet()> has to return a valid path/filename for the
stylesheet requested.

B<getDOM()> has to return the DOM later used by the stylesheet
processor.

the B<registerEvents> is slightly different implemented than other
event or callback functions. It will not recieve any context data,
since it is called even before the B<run> function, that creates the
context. It should return an array containing the names of the
explicit events handled by the script.

B<setHttpHeader> should return a hash of headers (but not the
Content-Type). This can be used to set the I<nocache> pragma, to set
or remove cookies. The keys of the hash must be the same as the named
parameters of CGI.pm's header method.

The last function B<getXSLTParameter> is called by B<serialization>
just before the xslt processing is done. This alows to pass up to 256
parameters to the processor. This function should return a hash or
undefined. The hash will be transformed to fit the XML::LibXSLT
interface, so one can simply pass a hash of strings to
CGI::XMLApplication.

=head2 Helperfunctions for internal use

=over 4

=item function checkPush LIST

This function searches the query string for a parameter with the
passed name. The implementation is "imagesave" meaning there is no
change in the code needed, if you switch from input.type=submit to
input.type=image or vv. The algorithm tests wheter a full name is
found in the querystring, if not it tries tests for the name expanded
by a '.x'. In context of events this function interprets each item
part in the query string list as an event. Because of that, the
algorithm returns only the first item matched.

If you use the event interface on this function, make sure, the
HTML-forms pass unique events to the script. This is neccessary to
avoid confusing behaviour.

=item function passthru( $boolean )

Since there are cases one needs to pass an untransformed XML Document
directly to the calling client this function allows to set such
directive for the serialization function from within the application.
Optional the function takes a single parameter, which shows if the
function should be used in set rather than get mode. If the parameter
is ommited the function returns the current passthru mode. Where TRUE
(1) means the XML DOM should be passed directly to the client and
FALSE (0) marks that the DOM must get processed first.

Additionally this function has a second FALSE state which is when
returned I<undef>. In such case the passthru state is not set.

If an application sets passthru by itself any external 'passthru'
parameter will be lost. This is usefull if one likes to avoid, someone
can fetch the plain (untransformed) XML Data.

=item function serialization()

This method renders the data stored in the DOM with
the stylesheet returned by the event handler. You should override
this function if you like to use a different way of displaying your
data.

For debugging purposes the parameter B<passthru> can be used to directly
pass the stringified DOM-tree to the client. (Quite useful, as I realized. :) )

To avoid the call of B<serialization()> one should set B<skipSerialization>.

   event_default {
      my $self = shift;
      # avoid serialization call
      $self->skipSerialization( 1 ); # use 0 to unset

      # now you can directly print to the client, but don't forget the
      # headers.

      return 0;
   }

If the serialization should be skipped, CGI::XMLApplication will not
print any headers. In such case the application is on its own to pass
all the output.

The algorithm used by serialization is simple:

=over 4

=item * request the appplication DOM through B<getDOM()>

=item * test for XML passthru

=item * get the stylesheet the application preferes through B<selectStylesheet()>

=item * parse the stylesheet

=item * transform the DOM with the stylesheet

=item * set Content-Type and headers

=item * return the content to the client

=back

If errors occour on a certain stage of serialization, the application
is stopped and the generated error messages are returned.

=item method panic SCALAR

This a simple error message handler. By default this function will
print some information to the client where the application
failed. While development this is a useful feature on production
system this may pass vunerable informations about the system to the
outside. To change the default behaviour, one may write his own panic
method or simply set I<$CGI::XMLApplication::Quiet> to 1. The latter
still causes the error page but does not send any error message.

The current implementation send the 404 status to the client if any
low level errors occour ( e.g. panic levels > -4 aka Application
Panic).  Commonly this really shows a "Not Found" on the application
Level. Application Panics will set the 500 error state. This makes
this implementation work perfect with a mod_perl installation.

In case L<mod_perl> is used to handle the script one likes to set
I<CGI::XMLApplication::Quiet> to 2 which will cause
CGI::XMLApplication just to return the error state while L<mod_perl>
does the rest.

=item method setPanicMsg $SCALAR

This useful method, helps to pass more specific error messages to the
user. Currently this method is not very sophisticated: if
the method is called twice, only the last string will be displayed.

=item function getPanicMsg

This method returns the panic message set by setPanicMsg().

=back

=head2 CGI Extras

The following functions are some neat features missing in
CGI.pm

=over 4

=item function checkFields LIST

This is an easy way to test wether all required fields are filled out
correctly. Called in array context the function returns the list of
missing parameter. (Different to param() which returns all parameter names).
In scalar context the function returns a boolean value.

=item function getParamHash LIST

This function is a bit better for general data processing as
the standard CGI::Vars function. While Vars sets a keys for each
parameter found in the query string, getFieldsAsHash returns only the
requested fields (as long they aren't NULL). This is useful in scripts
where the script itself handles different kind of data within the
same event.

Since the function relies on Vars the returned data has the same
structure Vars returns.

=back

=head2 some extra functions for stylesheet handling

CGI::XMLApplication had originally a rather strict design for XML/XSL
integration, therefore there are some specific functions to manipulate
data for such a system. The following functions left in the package,
so older applications does not have to be rewritten. Now I recommend,
to use the callback/ overriding system.

=over 4

=item method setStylesheetDir DIRNAME

alias for B<setStylesheetPath>

=item method setStylesheetPath DIRNAME

This method is for telling the application where the stylesheets can be found.
If you keep your stylesheets in the same directory as your script
-- generally a bad idea -- you might leave this untouched.

=item function getStylesheetPath

This function is only relevant if you write your own
B<serialization()> method. It returns the current path to the
application stylesheets.

=back

=head1 SEE ALSO

CGI, perlobj, perlmod, XML::LibXML, XML::LibXSLT

=head1 AUTHOR

Christian Glahn, christian.glahn@uibk.ac.at

=head1 VERSION

1.0.2
