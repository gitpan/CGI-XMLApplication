# $Id$

package CGI::XMLApplication;

# ################################################################
# $Revision: 1.2 $
# $Author: cb13108 $
#
# (c) 2001 Christian Glahn <christian.glahn@uibk.ac.at>
# All rights reserved.
# 
# This code is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# ################################################################

# ################################################################
# module loading and global variable initializing
# ################################################################
use vars qw( @ISA $VERSION @panic $DEBUG $STYLESHEET_CALLBACK
             $DOM_CALLBACK $SETEVENT_CALLBACK );
use CGI;
use Carp;

# ################################################################
# inheritance
# ################################################################
@ISA = qw( CGI );
# ################################################################
$VERSION = "0.8.1"; 

# ################################################################
# general configuration
# ################################################################

# for internationalization this should be read from a separate
# configfile.
@panic = (
          'No Stylesheet specified! ',
          'Stylesheet is not available! ',
          'Event not defined',
          'Application Error',
         );

# extra callback names
$STYLESHEET_CALLBACK = "selectStylesheet";
$DOM_CALLBACK        = "requestDOM";
$SETEVENT_CALLBACK   = "registerEvents";

# The Debug Level
$DEBUG = 0;

# ################################################################
# methods
# ################################################################
sub new {
  my $class = shift;
  $self = $class->SUPER::new( @_ );
  bless $self, $class;

  $self->{XML_CGIAPP_HANDLER_}    = [];
  $self->{XML_CGIAPP_STYLESHEET_} = [];
  $self->{XML_CGIAPP_STYLESDIR_}  = '';

  # register the events to handle
  if ( my $func = $self->can( $SETEVENT_CALLBACK ) ){
    # warn "[CGI::XMLApplication] set event names\n";
    $self->setEventList( $self->$func() );
  }

  return $self;
}

# ################################################################
# straight forward coded methods

# application related ############################################
# both functions are only for backward compatibilty with older scripts
sub setDebugLevel {
  $DEBUG = $_[1];
  warn "[CGI::XMLAppliction] new debug level is " . $_[1] . "\n";
}

sub getDebugLevel     { $DEBUG; }

# dom related ####################################################
sub getDOM            { $_[0]->{XML_CGIAPP_DOM_};}
sub setDOM            { $_[0]->{XML_CGIAPP_DOM_} = $_[1];}

# stylesheet directory information ###############################
sub setStylesheetDir  { $_[0]->{XML_CGIAPP_STYLESDIR_} = $_[1];}
sub setStylesheetPath { $_[0]->{XML_CGIAPP_STYLESDIR_} = $_[1];}
sub getStylesheetDir  { $_[0]->{XML_CGIAPP_STYLESDIR_}; }

# stylesheet list (since we provide multiple stylesheets) ########
sub setStylesheetList { my $s=shift; $s->{XML_CGIAPP_STYLESHEET_} = [ @_ ]; }
sub getStylesheetList { @{$_[0]->{XML_CGIAPP_STYLESHEET_}}; }

# event related ##################################################
sub setEventList      { my $s=shift; $s->{XML_CGIAPP_HANDLER_} = [ @_ ];}
sub addEvent          { my $s=shift; push @{$s->{XML_CGIAPP_HANDLER_}}, @_;}
sub getEvent          { @{ $_[0]->{XML_CGIAPP_HANDLER_} }; }

sub testEvent         { return $_[0]->checkPush( $_[0]->getEvent() ); }

sub deleteEvent       {
  my $self = shift;
  if ( scalar @_ ){
    foreach ( @_ ) {
      warn "[XML::CGIAppliction] delete event $_\n"
        if $self->getDebugLevel() > 8 ;
      $self->delete( $_ );
      $self->delete( $_.'.x' );
      $self->delete( $_.'.y' );
    }
  }
  else {
    foreach ( @{ $self->{XML_CGIAPP_HANDLER_} } ){
      warn "[XML::CGIAppliction] delete event $_\n"
        if $self->getDebugLevel() > 8 ;
      $self->delete( $_ );
      $self->delete( $_.'.x' );
      $self->delete( $_.'.y' );
    }
  }
}

sub sendEvent         {
  warn "[CGI::XMLAppliction] send event " . $_[1] ."\n"
    if $_[0]->getDebugLevel() == 10 ;
  $_[0]->deleteEvent();
  $_[0]->param( -name=>$_[1] , -value=>1 );
}

# error handling #################################################
sub setPanicMsg       { $_[0]->{XML_CGIAPP_PANIC_} = $_[1] }
sub getPanicMsg       { $_[0]->{XML_CGIAPP_PANIC_} }

# ################################################################
# events

# default event handler prototypes
sub event_init    {}
sub event_exit    {}
sub event_default { return -1 }

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

# cookies are only application related, through these functions we
# provide a passthrough mechanism to get and set cookies.
sub setCookie         {$_[0]->{XML_CGIAPP_COOKIE_} = $_[1]}
sub getCookie         {$_[0]->{XML_CGIAPP_COOKIE_}}
sub setContentType    {$_[0]->{XML_CGIAPP_CONTENT_TYPE_} = $_[1]}
sub getContentType    {$_[0]->{XML_CGIAPP_CONTENT_TYPE_}}

# helper functions which were missing in CGI.pm
sub checkFields{
  my $self = shift;
  my @missing = grep {
    not length $self->param( $_ ) || $self->param( $_ ) =~ /^\s*$/
  } @_;
  return wantarray ? @missing : ( @$missing >= 0 ? undef : 1 );
}

sub getFieldsAsHash {
  my $self = shift;
  my $ptrHash = $self->Vars;
  my $ptrRV   = {};

  my @aMatch  = grep {
    exists $ptrHash->{$_} && $ptrHash->{$_} !~ /^[\s\0]*$/
  } @_;

  map { $ptrRV->{$_} = $ptrHash->{$_} } @aMatch;

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
sub run {
  my $self = shift;
  my $sid = -1;
  my $ctxt = {@_}; # context hash

  $self->event_init($ctxt);

  if ( my $n = $self->checkPush( $self->getEvent() ) ) {
    if ( my $func = $self->can( 'event_'.$n ) ) { $sid = $self->$func($ctxt) }
    else                                        { $sid = -3; }
  }

  if ( $sid == -1 ){
    $sid = $self->event_default($ctxt);
  }
  $self->event_exit($ctxt);

  # if we allready panic, don't try to render
  if ( $sid >= 0 ) {
    $sid = $self->serialization( $ctxt );
  }

  $self->panic( $sid, $ctxt );
}


sub serialization {
  my $self = shift;
  my $ctxt = shift;
  my $dl       = $self->getDebugLevel();
  my $id;

  my $xml_doc = $self->getDOM();
  if ( not defined $xml_doc ) {
    if ( my $func = $self->can( $DOM_CALLBACK ) ) {
      warn "[CGI::XMLApplication] DOM Request callback \n" if $dl == 10;
      $xml_doc = $self->$func( $ctxt );
    }

    if ( not defined $xml_doc ) {
      warn "[XML::CGIAppliction] no DOM defined; use empty DOM\n" if $dl == 10;
      $xml_doc = XML::LibXML::Document->new;
    }
  }

  if( length  $self->param( 'passthru' ) ) {
    # this is a useful feature for DOM debugging
    warn "[XML::CGIAppliction] attempt to pass the DOM to the client\n"
      if $dl == 10;
    print $self->header( -type=>'text/xml'  );
    # my $cookie = $self->getCookie();
    # if ( defined $cookie ) {
    #   print "<COOKIE=> '". $cookie . "'\n\n";
    # }

    print $xml_doc->toString();

    return 0;
  }

  my $file = undef;
  if( my $func = $self->can( $STYLESHEET_CALLBACK ) ) {
    # warn "[CGI::XMLApplication] call stylesheet selector\n";
    $file = $self->$func( $ctxt );
  }
  else {
    # backward compatibility
    # generate the stylesheet filename.
    $file = $self->getStylesheetDir() . ($self->getStylesheetList())[$id];
  }

  warn "[CGI::XMLApplication] filename is $file \n" if $dl > 5;

  # we only do the rendering if the stylesheet is available from our
  # viewpoint.

  if ( -f $file && -r $file ) {
    require XML::LibXML;
    require XML::LibXSLT;

    # prepare default values
    my %header = ();
    my $cookie = $self->getCookie();

    %header = ( -cookie=>$cookie ) if $cookie;

    my $parser = XML::LibXML->new();
    my $xslt   = XML::LibXSLT->new();

    my ( $xsl_dom, $stylesheet, $res );
    # this first step is for double checking, since xsl has to be valid
    # XML, too.
    eval {
      $xsl_dom  = $parser->parse_file( $file );
    };
    if ( $@ ) {
      warn "Corrupted Stylesheet:\n broken XML\n". $@ if $dl > 3;
      $self->setPanicMsg( "Corrupted document:\n broken XML\n". $@ );
      return -2;
    }

    warn( "[CGI::XMLApplication] parsed stylesheet file ",
          ref( $xsl_dom ) ,
          "\nCGI::XMLApplication prepare stylesheet\n" )
      if $dl > 8;

    eval {
      # we simply can't do this, since libxslt will trash the stylesheet dom
      # which will cause strange segfaults in several cases.

      # $stylesheet = $xslt->parse_stylesheet( $xsl_dom ); # never uncomment!!

      # therefore i'll parse the stylesheet again, but in this case
      # the error messages will be more xsl related that in the first
      # XML validation run. i know, this IS is an overhead, because
      # parsing the same file twice, but it will return better
      # errormessages.
      $stylesheet = $xslt->parse_stylesheet_file( $file );
    };
    if( $@ ) {
      warn "Corrupted Stylesheet:\n". $@ ."\n" if $dl > 3;
      $self->setPanicMsg( "Corrupted Stylesheet:\n". $@ );
      return -2;
    }
    warn "CGI::XMLApplication do tranform\n" if $dl > 8;
    eval {
      $res = $stylesheet->transform( $xml_doc );
    };
    if( $@ ) {
      warn "Broken Transformation:\n". $@ ."\n" if $dl > 3;
      $self->setPanicMsg( "Broken Transformation:\n". $@ );
      return -2;
    }

    # this is a workaround for the encoding bug in XML::LibXML < 0.95
    if ($XML::LibXSLT::VERSION >= 1.03) {
      $header{-type} = $self->{XML_CGIAPP_CONTENT_TYPE_}
                       || $stylesheet->media_type;
      $header{-charset} = $stylesheet->output_encoding;
      # warn "[CGI::XMLApplication] Output $type, $encoding\n";
    }

    # warn "CGI::XMLApplication do output\n";
    # we want nice xhtml and since the output_string does not the
    # right job
    my $out_string= undef;

    warn "get output string\n" if $dl > 9;
    eval {
      $out_string =  $stylesheet->output_string( $res );
    };
    warn "CGI::XMLApplication rendered output\n" if $dl == 10;
    if ( $@ ) {
      warn "Corrupted Output:\n". $@ ."\n" if $dl > 3 ;
      $self->setPanicMsg( "Corrupted Output:\n". $@ );
      return -2;
    }
    else {
      # do the output
      print $self->header( %header );
      $out_string =~ s/\/>/ \/>/g; # yes, this is time consuming ... :(
      print $out_string;
      warn "CGI::XMLApplication output printed\n" if $dl == 10;
    }
    warn "post segfault test\n" if $dl == 10;
    $id = 0;
  }
  else {
    warn "panic stylesheet file $file does not exist\n" if $dl > 3;
    $self->setPanicMsg( "$file" );
    $id = -2;
  }
  return $id;
}

sub panic {
  my ( $self, $pid ) = @_;
  return unless $pid < 0;
  $pid++;
  $pid*=-1;
  my $str = "CGI::XMLApplication PANIC $pid :" .  $panic[$pid] ;
  # this is nice for debugging from logfiles...
  warn $str ."\n". $self->getPanicMsg();
  print $self->header( 'text/html' ) ,$self->b($str) ,"<br />\n";
  print "( <pre>".$self->getPanicMsg() , "</pre> )<br />\n\n";
  print "Please Contact the Systemadminstrator<br />\n";

}

1;
# ################################################################
__END__

=head1 NAME

CGI::XMLApplication -- Object Oriented Interface for CGI Script Applications

=head1 SYNOPSIS

  use CGI::XMLApplication;

  $script = new CGI::XMLApplication;
  $script->setStylesheetList( @STYLESHEETS );

  # either this for simple scripts
  $script->run();
  # or if you need more controll ...
  $script->run(%context_hash);

=head1 DESCRIPTION

CGI::XMLApplication is a CGI application class, that intends to enable
perl artists to implement CGIs that make use of XML/XSLT
functionality, without taking too much care about specialized
errorchecking. Also it is ment to provide the power of the
L<XML::LibXML>/ L<XML::LibXSLT> module package. CGI::XMLApplication's
serialization process pays a lot attention of keeping an application
stable to run. So a programmer has not to bother about some of
XML::LibXML/ XML::LibXSLT serialization pitfalls.

This class module extends the CGI class. While all functionality of
the original CGI package is still available, it should be not such a
big problem, to port existing scripts to CGI::XMLApplication.

CGI::XMLApplication, intended to be an application class should make
writing of CGI scripts extremly easy. Especially because of the use of
object orientated concepts, this class enables much more transparent
implemententations with complex functionality compared to what is
possible with standard CGI-scripts.

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
button or an image, CGI::XMLApplication lets the programmer specify
the handler for such events.

Therefore final application class is not ment to have a constructor
anymore. All functionality should be encapsulated into implicit or
explicit event handlers. Because of a lack in Perl's OO implementation
the call of a superclass constructor before the current constructor
call is not default behavior in Perl. For that reason I decided to
have special 'events' to enable the application to initialize correctly,
excluding the danger of leaving important variables undefined. On the other
hand this forces the programmer to implement the script rather problem
orientated, than the class.

Another design aspect for CGI::XMLApplication is the strict differentiation
between CODE and PRESENTATION. IMHO this, in fact being one of the
major problems in traditional CGI programming.  To implement this, the
XML::LibXML and XML::LibXSLT modules are used.  Each CGI Script should
generate an XML-DOM, that can be processed with a given stylesheet.

B<Pay attention that XML-DOM means the DOM of XML::LibXML and not XML::DOM!>

=head2 What are Events and how to catch them

Most CGI handle the result of HTML-Forms or similar requests from clients.
Analouge to GUI Programming, CGI::XMLApplication calls this an B<event>.
Spoken in CGI/HTML-Form words, a CGI-Script handles the various situations
a clients causes by pushing a submit button or follows a special link. 

An event of CGI::XMLApplication has the same B<name> as the input
field, that should cause the event. The following example should
illustrate this a little better:

    <!-- SOME HTML CODE -->
    <input type="submit" name="dummy" value="whatever" />
    <!-- SOME MORE HTML :) -->

If a user clicks the submitbutton and you have registered the event
name B<dumm> for your script, CGI::XMLApplication will try to call the
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
declare separate events for input images. E.g. evname makes
CGI::XMLApplication look for evname B<and> evname.x in the
querystring.

Some programmer are suspious which event CGI::XMLApplication will
call.  The function B<testEvent> checks all events if one is valid and
returns the name of event. Much more important is the possibility to
send B<error events> from the event_init() function. This is done with
the B<sendEvent> Function. This will set a new parameter to the CGI'S
querystring after removing all other events. B<One can only send
events that are already registred!>.

CGI::XMLApplication doesn't implement an event queqe. For GUI
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
method B<run()>.  Since this method is extremly simple and transparent to
any kind of display type, there should be no need to override this
function.

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

If the B<selectStylesheet> is not implemented the CGI::XMLApplication
will assume the returned value as id to a stylesheet list set by
setStylesheetList(). Basicly this is done for backward compatibility
reasons. An application better implements the B<selectStylesheet>
callback, to end up with a more strict structure.

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

=item method setEventList LIST

This method, usually called during the initialization of the
application, sets a list of events available. If you use this method
you might lose events already defined by a superclass. Therefore this
way of event definition is only useful if you are sure that you only
need to handle events you have control of.

=item function testEvent

Sometimes it is nesseccary to check which event is relevant for the
current script. This function selects the name of the currently valid
callback. If this function returns undef, the default event is active.

=item method addEvents LIST

addEvents() also takes a list of events the application will
handle. Contrary to setEventList() this does not override previously
defined events. This method is almost always the better solution if
the application is not directly based on CGI::XMLApplication.
#what does directly based mean here?

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

     ... your error handling code here ...

     return -4 if $panic;  # just for illustration :D
     return 0;
  }

=back

=head2 Implicit Events

CGI::XMLApplication knows three implicit events which are more or less
independent to the client's response: They are 'init', 'exit', and
'default'.

If there is need to override one of these handler -- and I hope
there will be ;) -- the particular event should call the
related event handler of its superclass as first action. This might be
skipped, if the function should do everything right by itself.
I prefere the first technique, because it is more secure and
makes things easier to debug.
#example

Each event has a single Parameter, the context. This is a hash
reference, where the user can store whatever needed. This context is
usefull to pass scriptwide data between callbacks and event functions
around.

=over 4

=item event_init

The init event is set before the CGI::XMLApplication tries to evaluate
any of the script's parameters. Therefore the event_init method should
be used to initialize the application.

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

=head2 Extra Callbacks

There are some extra callbacks may implemented:

=over 4

=item * selectStylesheet

=item * requestDOM

=item * registerEvents

=back

These two callbacks are used by the render_to_client function, to
create the content related datastructure. Like event functions these
callback functions have to be implemented as class member, and like
event funcitons the functions will have the context passed as the
single parameter.

B<selectStylesheet()> has to return a valid path/filename for the
stylesheet requested.

B<requestDOM()> has to return the DOM later used by the stylesheet
processor.

the B<registerEvents> is slightly different implemented than other
event or callback functions. It will not recieve any context data,
since it is called even before the B<run> function, that creates the
context. It should return an array containing the names of the
explicit events handled by the script.

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

=item method setCookie CGI::COOKIE

=item function getCookie

If you ever need to send a cookie to the client, you should use this
method/function pair. It helps to automatically generate the
correct header send to the client.

=item function serialization()

This method renders the data stored in the DOM with
the stylesheet returned by the event handler. You should override
this function if you like to use a different way of displaying your
data.

You may not override the B<serialization> function, if you just handle
XML data that should be transformed XSLT stylesheets. In somecases the
returned data is not XML but for instance in PDF format, while most of
the time XML Data is still used. For such cases the serialization
function can be overridden and the special output functionality can be
added.

The return value of B<serialization> should be greater than zero (0)
if no error occured. Otherwise the panic() function will be called and
will send an error message to the client.

For debugging purposes the parameter B<passthru> can be used to directly
pass the stringified DOM-tree to the client. (Quite useful, as I realized. :) )

=item method panic SCALAR

This a simple error message handler

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

=item function getFieldsAsHash LIST

This function is a bit better for general data processing as
the standard CGI::Vars function. While Vars sets a keys for each
parameter found in the query string, getFieldsAsHash returns only the
requested fields (as long they aren't NULL). This is useful in scripts
where the script itself handles different kind of data within the
same event.

Since the function relies on Vars the returned data has the same
structure Vars returns.

=back

=head2 XML/XSL Integration (obsolete)

CGI::XMLApplication had originally a rather strict design for XML/XSL
integration, therefore there are some specific functions to manipulate
data for such a system. The following functions left in the package,
so older applications does not have to be rewritten. Now I recommend,
to use the callback/ overriding system.


=item method setDOM XML::LibXML::Document

This method sets a user initialized DOM to the class. Usually this is
done once per application. Be aware, that the DOM is passed straight
to the XSLT renderer. If you would like to implement your own
B<serialization()> method (which is described below), you may set a
different DOM.

Since the current version provides a requestDOM callback, a programmer
may not call setDOM anymore from within the events, but store the
output DOM in the applications context. In this case there B<has to> be
the B<requestDOM> function implemented.

=over 4

=item function getDOM

This method is the inversion of setDOM. It returns the DOM of the current
application set by setDOM. This function will be quite helpful if
you have to access the DOM in different parts of the application.
Returns what ever you set (default XML::XPath::Node::Element)

=item method setStylesheetDir DIRNAME

alias for B<setStylesheetPath>

=item method setStylesheetPath DIRNAME

This method is for telling the application where the stylesheets can be found.
If you keep your stylesheets in the same directory as your script
-- generally a bad idea -- you might leave this untouched.

=item function getStylesheetDir

This function is only relevant if you write your own
B<serialization()> method. It returns the current path to the
application stylesheets.

=item method setStylesheetList LIST

The stylesheet list should include all filenames of the stylesheets
the script wants to access. Depending on the event, the stylesheet is
accessed by the event handler's return value. For example if 0 is
returned, the first stylesheet in the list is selected.

Example:

 sub event_init {
    my $self = shift;
    my rv = $self->SUPER::event_init();

   ...do something here...

    $self->setStylesheetList( 'default.xsl', 'error.xsl' ) ;

   ...do something here...

 }

 sub event_default {
    my $self = shift;
    $self->SUPER::event_default();

   ...do something here...

    return 1 if $errorcondition == 1; #error.xsl is used for rendering
    return 0; #default.xsl is used for rendering
 }

=item function getStylesheetList

This inversion of setStylesheetList returns an array with the
stylesheet's names. This function is used by the B<serialization>
function.

=back

=head1 SEE ALSO

CGI, perlobj, perlmod, XML::LibXML, XML::LibXSLT

=head1 AUTHOR

Christian Glahn, christian.glahn@uibk.ac.at

=head1 VERSION

0.8.1
