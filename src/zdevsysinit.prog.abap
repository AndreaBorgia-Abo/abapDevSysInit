REPORT zdevsysinit.

* Todo: ability to reset/re-run some items
*PARAMETERS p_reset TYPE abap_bool AS CHECKBOX DEFAULT abap_false.

PARAMETERS p_user TYPE rfcalias.
PARAMETERS p_token TYPE rfcexec_ext.
PARAMETERS p_rfcdst TYPE abap_bool AS CHECKBOX DEFAULT abap_false.
PARAMETERS p_certi TYPE abap_bool AS CHECKBOX DEFAULT abap_false.
PARAMETERS p_abapgt TYPE abap_bool AS CHECKBOX DEFAULT abap_true.
PARAMETERS p_repos TYPE abap_bool AS CHECKBOX DEFAULT abap_false.

DATA out TYPE REF TO if_demo_output.

*--------------------------------------------------------------------*
CLASS lcx_error DEFINITION INHERITING FROM cx_static_check.
ENDCLASS.
*--------------------------------------------------------------------*


*--------------------------------------------------------------------*
CLASS rfc_destination DEFINITION CREATE PUBLIC.
*--------------------------------------------------------------------*

  PUBLIC SECTION.
    CLASS-METHODS exists IMPORTING i_name        TYPE rfcdest
                         RETURNING VALUE(result) TYPE abap_bool.

    METHODS execute IMPORTING i_name  TYPE string
                              i_user  TYPE rfcalias
                              i_token TYPE rfcdisplay-rfcexec
                              i_reset TYPE abap_bool DEFAULT abap_false.
  PROTECTED SECTION.
    METHODS create_rfc_destination IMPORTING i_user  TYPE rfcalias
                                             i_token TYPE rfcdisplay-rfcexec.
    METHODS delete_rfc_destination.
    METHODS check_existence IMPORTING i_name        TYPE rfcdest
                            RETURNING VALUE(result) TYPE abap_bool.

  PRIVATE SECTION.
    DATA name TYPE rfcdest VALUE 'GITHUB' ##NO_TEXT.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS rfc_destination IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD execute.

    name = i_name.

    IF check_existence( name ).

      IF i_reset = abap_true.
        delete_rfc_destination( ).
        out->write( |RFC destination { name } deleted| ).
      ELSE.
        out->write( |RFC destination { name } already exists, not changed| ).
        RETURN.
      ENDIF.

    ENDIF.

    create_rfc_destination( i_user  = i_user
                            i_token = i_token ).
    out->write( |RFC destination { name } created| ).

  ENDMETHOD.


  METHOD create_rfc_destination.

    CALL FUNCTION 'RFC_MODIFY_HTTP_DEST_TO_EXT'
      EXPORTING
        destination                = name
        action                     = 'I'
        authority_check            = abap_true
        servicenr                  = '443'
        server                     = 'github.com'
        user                       = i_user
        password                   = i_token
        sslapplic                  = 'ANONYM'
        logon_method               = 'B'
        ssl                        = abap_true
      EXCEPTIONS
        authority_not_available    = 1
        destination_already_exist  = 2
        destination_not_exist      = 3
        destination_enqueue_reject = 4
        information_failure        = 5
        trfc_entry_invalid         = 6
        internal_failure           = 7
        snc_information_failure    = 8
        snc_internal_failure       = 9
        destination_is_locked      = 10
        invalid_parameter          = 11
        OTHERS                     = 12.
    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.


  METHOD exists.
    result = NEW rfc_destination( )->check_existence( i_name ).
  ENDMETHOD.


  METHOD delete_rfc_destination.

    CALL FUNCTION 'RFC_MODIFY_HTTP_DEST_TO_EXT'
      EXPORTING
        destination                = name
        action                     = 'D'
        authority_check            = abap_true
      EXCEPTIONS
        authority_not_available    = 1
        destination_already_exist  = 2
        destination_not_exist      = 3
        destination_enqueue_reject = 4
        information_failure        = 5
        trfc_entry_invalid         = 6
        internal_failure           = 7
        snc_information_failure    = 8
        snc_internal_failure       = 9
        destination_is_locked      = 10
        invalid_parameter          = 11
        OTHERS                     = 12.

    IF sy-subrc <> 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.

  ENDMETHOD.

  METHOD check_existence.
    result = NEW cl_dest_factory( )->exists( i_name ).
  ENDMETHOD.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS repo DEFINITION CREATE PUBLIC.
*--------------------------------------------------------------------*

  PUBLIC SECTION.
    METHODS setup IMPORTING i_name    TYPE string
                            i_package TYPE devclass
                            i_url     TYPE string
                            i_reset   TYPE abap_bool DEFAULT abap_false.
    METHODS constructor RAISING zcx_abapgit_exception.

  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA repos TYPE zif_abapgit_persistence=>ty_repos.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS repo IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD constructor.
    repos = zcl_abapgit_persist_factory=>get_repo( )->list( ).
  ENDMETHOD.

  METHOD setup.
    DATA: repo TYPE REF TO zcl_abapgit_repo_online.

    LOOP AT repos INTO DATA(repo_data) WHERE package = i_package.
      out->write( |Package { i_package } already used in repo { repo_data-local_settings-display_name }| ).
      RETURN.
    ENDLOOP.

    DATA(repo_srv) = zcl_abapgit_repo_srv=>get_instance( ).
    TRY.
        repo = CAST #( repo_srv->new_online(
          iv_url          = i_url
          iv_package      = i_package
          iv_display_name = i_name ) ).
        out->write( |Repo { i_name } created| ).

        DATA(log) = CAST zif_abapgit_log( NEW zcl_abapgit_log( ) ).
        DATA(background) = CAST zif_abapgit_background( NEW zcl_abapgit_background_pull( ) ).

        background->run(
          io_repo     = repo
          ii_log      = log
          it_settings = VALUE #( ) ).

        out->write( log->get_messages( ) ).

      CATCH zcx_abapgit_exception INTO DATA(error).
        out->write( |Create repo { i_name } failed: { error->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS ag_standalone DEFINITION CREATE PUBLIC.
*--------------------------------------------------------------------*

  PUBLIC SECTION.
    METHODS execute RAISING lcx_error.
  PROTECTED SECTION.
    TYPES t_source_lines TYPE STANDARD TABLE OF abaptxt255 WITH EMPTY KEY.
    DATA url TYPE string VALUE `https://raw.githubusercontent.com/abapGit/build/main/zabapgit_standalone.prog.abap`.
    METHODS get_source RETURNING VALUE(result) TYPE string
                       RAISING   lcx_error.
    METHODS insert_report IMPORTING source_lines TYPE t_source_lines
                          RAISING
                                    lcx_error.
    METHODS validate_and_split_source IMPORTING source        TYPE string
                                      RETURNING VALUE(result) TYPE ag_standalone=>t_source_lines
                                      RAISING   lcx_error.
  PRIVATE SECTION.
    METHODS fail_on_nonzero_subrc IMPORTING message TYPE string
                                  RAISING   lcx_error.
ENDCLASS.

*--------------------------------------------------------------------*
CLASS ag_standalone IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD execute.

    DATA(source) = get_source( ).
    DATA(source_lines) = validate_and_split_source( source ).

    insert_report( source_lines ).

  ENDMETHOD.


  METHOD get_source.

    cl_http_client=>create_by_url(
      EXPORTING
        url                = url
      IMPORTING
        client             = DATA(client)    " HTTP Client Abstraction
      EXCEPTIONS
        argument_not_found = 1
        plugin_not_active  = 2
        internal_error     = 3
        OTHERS             = 4
    ).
    fail_on_nonzero_subrc( `Could not create HTTP client` ).

    client->send(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        http_invalid_timeout       = 4
        OTHERS                     = 5
    ).

    fail_on_nonzero_subrc( |HTTP Send failure| ).

    client->receive(
      EXCEPTIONS
        http_communication_failure = 1
        http_invalid_state         = 2
        http_processing_failed     = 3
        OTHERS                     = 4
    ).
*    fail_on_nonzero_subrc( |HTTP Receive failure| ).

    client->response->get_status(
      IMPORTING
        code   = DATA(code)
        reason = DATA(reason)
    ).
    IF code <> 200.
      out->write( |HTTP request failure { code }: { reason }| ).
      RAISE EXCEPTION TYPE lcx_error.
    ENDIF.

    result = client->response->get_cdata( ).

  ENDMETHOD.


  METHOD fail_on_nonzero_subrc.
    IF sy-subrc <> 0.
      out->write( message ).
      RAISE EXCEPTION TYPE lcx_error.
    ENDIF.
  ENDMETHOD.


  METHOD insert_report.

    CALL FUNCTION 'RPY_PROGRAM_INSERT'
      EXPORTING
*       application       = 'X'
*       authorization_group = space
        development_class = '$TMP'
*       edit_lock         = space
*       log_db            = space
        program_name      = 'ZABAPGIT_STANDALONE'
*       program_type      = '1'
*       r2_flag           = space
*       temporary         = space
        title_string      = 'abapGit Standalone'
*       transport_number  = space
*       save_inactive     = space
        suppress_dialog   = abap_true
*       status            = space
*       uccheck           = 'X'
      TABLES
*       source            =
        source_extended   = source_lines
      EXCEPTIONS
        already_exists    = 1
        cancelled         = 2
        name_not_allowed  = 3
        permission_error  = 4
        OTHERS            = 5.

    fail_on_nonzero_subrc( `Failed to create ZABAPGIT_STANDALONE` ).

  ENDMETHOD.


  METHOD validate_and_split_source.

    IF substring( val = source len = 26 ) <> `REPORT zabapgit_standalone`.
      out->write( `Did not retrieve expected abapGit standalone source` ).
      RAISE EXCEPTION TYPE lcx_error.
    ENDIF.

    DATA source_lines TYPE t_source_lines.
    SPLIT source AT cl_abap_char_utilities=>newline INTO TABLE result.

  ENDMETHOD.

ENDCLASS.

*--------------------------------------------------------------------*
CLASS ltc_ag_standalone DEFINITION FINAL FOR TESTING
  DURATION SHORT
  RISK LEVEL HARMLESS
  INHERITING FROM ag_standalone.
*--------------------------------------------------------------------*

  PROTECTED SECTION.
    METHODS get_source REDEFINITION.
    METHODS insert_report REDEFINITION.

  PRIVATE SECTION.
    DATA report_lines TYPE STANDARD TABLE OF string WITH EMPTY KEY.
    CLASS-DATA source TYPE string.
    CLASS-METHODS class_setup.

    METHODS setup.

    METHODS response_content_ok FOR TESTING RAISING cx_static_check.
    METHODS report_inserted FOR TESTING RAISING cx_static_check.
    METHODS response_received FOR TESTING RAISING cx_static_check.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS ltc_ag_standalone IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD class_setup.
    out = cl_demo_output=>new( ).
  ENDMETHOD.

  METHOD setup.
    url = `https://raw.githubusercontent.com/pokrakam/abapDevSysInit/main/LICENSE`.
  ENDMETHOD.


  METHOD response_received.
    cl_abap_unit_assert=>assert_not_initial( get_source( ) ).
  ENDMETHOD.


  METHOD response_content_ok.
    source = get_source( ).
    DATA(header) = substring( val = source len = 11 ).
    cl_abap_unit_assert=>assert_equals( act = header
                                        exp = `MIT License` ).
  ENDMETHOD.


  METHOD report_inserted.

    DATA(local_source) = |REPORT zabapgit_standalone.\n{ get_source( ) }|.
    DATA(source_lines) = validate_and_split_source( local_source ).

    insert_report( source_lines ).

    cl_abap_unit_assert=>assert_not_initial( report_lines ).
    cl_abap_unit_assert=>assert_table_contains( line = `SOFTWARE.` table = report_lines ).

  ENDMETHOD.


  METHOD insert_report.
    report_lines = source_lines.
  ENDMETHOD.


  METHOD get_source.
    "Bit hacky, but let's only go out to GitHub once per test run
    IF source IS INITIAL.
      source = super->get_source( ).
    ENDIF.
    result = source.
  ENDMETHOD.

ENDCLASS.


*--------------------------------------------------------------------*
"!
"! SSL Certificate classes re-used from
"! https://github.com/sandraros/zcerti which re-used
"! https://github.com/Marc-Bernard-Tools/ABAP-Strust
"!
"! MIT License
"!
"! Copyright (c) 2024 sandraros
"!
"! Permission is hereby granted, free of charge, to any person obtaining a copy
"! of this software and associated documentation files (the "Software"), to deal
"! in the Software without restriction, including without limitation the rights
"! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
"! copies of the Software, and to permit persons to whom the Software is
"! furnished to do so, subject to the following conditions:
"!
"! The above copyright notice and this permission notice shall be included in all
"! copies or substantial portions of the Software.
"!
"! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
"! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
"! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
"! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
"! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
"! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
"! SOFTWARE.
CLASS zcx_certi_strust DEFINITION
  INHERITING FROM cx_static_check
  CREATE PUBLIC.

************************************************************************
* Trust Management Error
*
* Copyright 2021 Marc Bernard <https://marcbernardtools.com/>
* SPDX-License-Identifier: MIT
************************************************************************
  PUBLIC SECTION.

    INTERFACES if_t100_dyn_msg.
    INTERFACES if_t100_message.

    CLASS-DATA null TYPE string.

    METHODS constructor
      IMPORTING
        !textid   LIKE if_t100_message=>t100key OPTIONAL
        !previous LIKE previous OPTIONAL
        !msgv1    TYPE symsgv OPTIONAL
        !msgv2    TYPE symsgv OPTIONAL
        !msgv3    TYPE symsgv OPTIONAL
        !msgv4    TYPE symsgv OPTIONAL.

    "! Raise exception with text
    "! @parameter iv_text | Text
    "! @parameter ix_previous | Previous exception
    "! @raising zcx_certi_strust | Exception
    CLASS-METHODS raise
      IMPORTING
        !iv_text     TYPE clike
        !ix_previous TYPE REF TO cx_root OPTIONAL
      RAISING
        zcx_certi_strust.

    "! Raise exception with T100 message
    "! <p>
    "! Will default to sy-msg* variables. These need to be set right before calling this method.
    "! </p>
    "! @parameter iv_msgid | Message ID
    "! @parameter iv_msgno | Message number
    "! @parameter iv_msgv1 | Message variable 1
    "! @parameter iv_msgv2 | Message variable 2
    "! @parameter iv_msgv3 | Message variable 3
    "! @parameter iv_msgv4 | Message variable 4
    "! @parameter ix_previous | Previous exception
    "! @raising zcx_certi_strust | Exception
    CLASS-METHODS raise_t100
      IMPORTING
        VALUE(iv_msgid) TYPE symsgid DEFAULT sy-msgid
        VALUE(iv_msgno) TYPE symsgno DEFAULT sy-msgno
        VALUE(iv_msgv1) TYPE symsgv DEFAULT sy-msgv1
        VALUE(iv_msgv2) TYPE symsgv DEFAULT sy-msgv2
        VALUE(iv_msgv3) TYPE symsgv DEFAULT sy-msgv3
        VALUE(iv_msgv4) TYPE symsgv DEFAULT sy-msgv4
        !ix_previous    TYPE REF TO cx_root OPTIONAL
      RAISING
        zcx_certi_strust.

    "! Raise with text from previous exception
    "! @parameter ix_previous | Previous exception
    "! @raising zcx_certi_strust | Exception
    CLASS-METHODS raise_with_text
      IMPORTING
        !ix_previous TYPE REF TO cx_root
      RAISING
        zcx_certi_strust.

  PROTECTED SECTION.
  PRIVATE SECTION.

    CONSTANTS c_generic_error_msg TYPE string VALUE `An error occured`.

    CLASS-METHODS split_text_to_symsg
      IMPORTING
        !iv_text      TYPE string
      RETURNING
        VALUE(rs_msg) TYPE symsg.

ENDCLASS.



CLASS zcx_certi_strust IMPLEMENTATION.


  METHOD constructor ##ADT_SUPPRESS_GENERATION.

    super->constructor( previous = previous ).

    if_t100_dyn_msg~msgv1 = msgv1.
    if_t100_dyn_msg~msgv2 = msgv2.
    if_t100_dyn_msg~msgv3 = msgv3.
    if_t100_dyn_msg~msgv4 = msgv4.

    CLEAR me->textid.

    IF textid IS INITIAL.
      if_t100_message~t100key = if_t100_message=>default_textid.
    ELSE.
      if_t100_message~t100key = textid.
    ENDIF.

  ENDMETHOD.


  METHOD raise.

    DATA:
      lv_text TYPE string,
      ls_msg  TYPE symsg.

    IF iv_text IS INITIAL.
      lv_text = c_generic_error_msg.
    ELSE.
      lv_text = iv_text.
    ENDIF.

    ls_msg = split_text_to_symsg( lv_text ).

    " Set syst variables using generic error message
    MESSAGE e001(00) WITH ls_msg-msgv1 ls_msg-msgv2 ls_msg-msgv3 ls_msg-msgv4 INTO null.

    raise_t100( ix_previous = ix_previous ).

  ENDMETHOD.


  METHOD raise_t100.

    DATA ls_t100_key TYPE scx_t100key.

    IF iv_msgid IS NOT INITIAL.
      ls_t100_key-msgid = iv_msgid.
      ls_t100_key-msgno = iv_msgno.
      ls_t100_key-attr1 = 'IF_T100_DYN_MSG~MSGV1'.
      ls_t100_key-attr2 = 'IF_T100_DYN_MSG~MSGV2'.
      ls_t100_key-attr3 = 'IF_T100_DYN_MSG~MSGV3'.
      ls_t100_key-attr4 = 'IF_T100_DYN_MSG~MSGV4'.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_certi_strust
      EXPORTING
        textid   = ls_t100_key
        msgv1    = iv_msgv1
        msgv2    = iv_msgv2
        msgv3    = iv_msgv3
        msgv4    = iv_msgv4
        previous = ix_previous.

  ENDMETHOD.


  METHOD raise_with_text.

    raise(
      iv_text     = ix_previous->get_text( )
      ix_previous = ix_previous ).

  ENDMETHOD.


  METHOD split_text_to_symsg.

    CONSTANTS:
      lc_length_of_msgv           TYPE i VALUE 50,
      lc_offset_of_last_character TYPE i VALUE 49.

    DATA:
      lv_text    TYPE c LENGTH 200,
      lv_rest    TYPE c LENGTH 200,
      lv_msg_var TYPE c LENGTH lc_length_of_msgv,
      lv_index   TYPE sy-index.

    lv_text = iv_text.

    DO 4 TIMES.

      lv_index = sy-index.

      CALL FUNCTION 'TEXT_SPLIT'
        EXPORTING
          length = lc_length_of_msgv
          text   = lv_text
        IMPORTING
          line   = lv_msg_var
          rest   = lv_rest.

      IF lv_msg_var+lc_offset_of_last_character(1) = space OR lv_text+lc_length_of_msgv(1) = space.
        " keep the space at the beginning of the rest
        " because otherwise it's lost
        lv_rest = | { lv_rest }|.
      ENDIF.

      lv_text = lv_rest.

      CASE lv_index.
        WHEN 1.
          rs_msg-msgv1 = lv_msg_var.
        WHEN 2.
          rs_msg-msgv2 = lv_msg_var.
        WHEN 3.
          rs_msg-msgv3 = lv_msg_var.
        WHEN 4.
          rs_msg-msgv4 = lv_msg_var.
      ENDCASE.

    ENDDO.

  ENDMETHOD.
ENDCLASS.


CLASS zcx_certi DEFINITION
  INHERITING FROM cx_static_check
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS zcx_certi IMPLEMENTATION.
ENDCLASS.


*"* use this source file for the definition and implementation of
*"* local helper classes, interface definitions and type
*"* declarations

"! Constants taken from the standard include ICMDEF
INTERFACE lif_icmdef.

  CONSTANTS dp_plugin_op_chng_param TYPE i VALUE 8.

*---------------------------------------------------------------------
* Rueckgabewerte
* Sind mit icxx.h abzustimmen
* ...
*---------------------------------------------------------------------
  CONSTANTS icmeok       LIKE sy-subrc VALUE 0.
  CONSTANTS icmenotavail LIKE sy-subrc VALUE -6.

ENDINTERFACE.

"! Constants taken from the standard include TSKHINCL
INTERFACE lif_tskhincl.
***INCLUDE TSKHINCL.

*-------------------------------------------------------------------*/
* Constants for calls of the taskhandler-C-functions
*-------------------------------------------------------------------*/


*-------------------------------------------------------------------*/
* reference fields
*-------------------------------------------------------------------*/
  DATA th_opcode(1) TYPE x.
*--------------------------------------------------------------------*/
* Constants for calling function ThSysInfo
*--------------------------------------------------------------------*/
  ##NEEDED
  CONSTANTS opcode_icm LIKE th_opcode VALUE 35.
ENDINTERFACE.


CLASS zcl_certi_icm_trace DEFINITION
  FINAL
  CREATE PRIVATE .

  PUBLIC SECTION.
    TYPES tt_icm_lines TYPE STANDARD TABLE OF icm_lines WITH DEFAULT KEY.
    TYPES tv_certificate_line  TYPE c LENGTH 64.
    TYPES tt_certificate_line TYPE STANDARD TABLE OF tv_certificate_line WITH EMPTY KEY.
    TYPES:
      BEGIN OF ts_certificate,
        lines TYPE tt_certificate_line,
      END OF ts_certificate.
    TYPES tt_certificate TYPE STANDARD TABLE OF ts_certificate WITH DEFAULT KEY.
    TYPES:
      BEGIN OF ts_parsed_trace,
        certificates TYPE tt_certificate,
      END OF ts_parsed_trace.

    CLASS-METHODS create
      RETURNING
        VALUE(result) TYPE REF TO zcl_certi_icm_trace.

    METHODS delete_trace.

    METHODS get_parsed_trace
      RETURNING
        VALUE(result) TYPE ts_parsed_trace.

    METHODS get_raw_trace
      RETURNING
        VALUE(result) TYPE tt_icm_lines.

    METHODS get_trace_level
      RETURNING
        VALUE(result) TYPE icm_info-trace_lvl.

    METHODS set_trace_level
      IMPORTING
        value TYPE icm_info-trace_lvl DEFAULT 0.

  PROTECTED SECTION.

  PRIVATE SECTION.
    TYPES tt_icm_sinfo2 TYPE STANDARD TABLE OF icm_sinfo2 WITH DEFAULT KEY.

ENDCLASS.



CLASS zcl_certi_icm_trace IMPLEMENTATION.


  METHOD create.
    result = NEW #( ).
  ENDMETHOD.


  METHOD delete_trace.
    CALL FUNCTION 'ICM_RESET_TRACE'
      EXCEPTIONS
        icm_op_failed      = 1
        icm_not_authorized = 2
        OTHERS             = 3.
    IF sy-subrc <> 0.
      " TODO
    ENDIF.
  ENDMETHOD.


  METHOD get_parsed_trace.
    TYPES:
      BEGIN OF ts_trace_line,
        thread TYPE string,
        text   TYPE string,
      END OF ts_trace_line.
    TYPES tt_trace_line TYPE STANDARD TABLE OF ts_trace_line WITH EMPTY KEY.

    DATA(raw_trace) = get_raw_trace( ).

    FIND ALL OCCURRENCES OF REGEX `^\[Thr ([^\]]+)\] +([^ ].*)$`
        IN TABLE raw_trace
        RESULTS DATA(matches).

    DATA(trace_lines) = VALUE tt_trace_line( ).
    LOOP AT matches REFERENCE INTO DATA(match).
      DATA(raw_trace_line) = REF #( raw_trace[ match->line ] ).
      INSERT VALUE #( thread = substring( val = raw_trace_line->lines
                                          off = match->submatches[ 1 ]-offset
                                          len = match->submatches[ 1 ]-length )
                      text   = substring( val = raw_trace_line->lines
                                          off = match->submatches[ 2 ]-offset ) )
            INTO TABLE trace_lines.
    ENDLOOP.

    TYPES:
      BEGIN OF ts_certificate_in_trace,
        begin_line TYPE sytabix,
        end_line   TYPE sytabix,
      END OF ts_certificate_in_trace.
    TYPES tt_certificate_in_trace TYPE STANDARD TABLE OF ts_certificate_in_trace WITH EMPTY KEY.

    DATA(certificates_in_trace) = VALUE tt_certificate_in_trace( ).
    LOOP AT trace_lines REFERENCE INTO DATA(trace_line)
        WHERE text = `-----BEGIN CERTIFICATE-----`
           OR text = `-----END CERTIFICATE-----`.
      CASE substring( val = trace_line->text
                      off = 5
                      len = 3 ).
        WHEN 'BEG'.
          DATA(certificate_in_trace) = VALUE ts_certificate_in_trace( begin_line = sy-tabix ).
        WHEN 'END'.
          certificate_in_trace-end_line = sy-tabix.
          INSERT certificate_in_trace INTO TABLE certificates_in_trace.
      ENDCASE.
    ENDLOOP.

    LOOP AT certificates_in_trace ASSIGNING FIELD-SYMBOL(<certificate_in_trace>).
      INSERT VALUE #( lines = REDUCE #( INIT t = VALUE tt_certificate_line( )
                                        FOR <trace_line> IN trace_lines
                                            FROM <certificate_in_trace>-begin_line
                                            TO   <certificate_in_trace>-end_line
                                        NEXT t = VALUE #( BASE t
                                                          ( CONV #( <trace_line>-text ) ) ) ) )
            INTO TABLE result-certificates.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_raw_trace.
    " Credit: subroutine ICMAN_SHOW_TRACE in RSMONICM.
    DATA p_filename      TYPE icm_lines-lines VALUE 'dev_icm'.
    DATA p_first_n_lines TYPE i               VALUE 0.
    DATA p_last_n_lines  TYPE i               VALUE 0.
    CALL FUNCTION 'ICM_READ_TRC_FILE2'
      EXPORTING
        icm_filename      = p_filename
        icm_last_n_lines  = p_last_n_lines
        icm_first_n_lines = p_first_n_lines
      TABLES
        lines             = result
      EXCEPTIONS
        icm_open_failed   = 1
        OTHERS            = 2.
    IF sy-subrc <> 0.
      " TODO
    ENDIF.
  ENDMETHOD.


  METHOD get_trace_level.
    DATA(icm_info_data) = VALUE icm_info( ).
    DATA(dummy_icm_servlist2) = VALUE tt_icm_sinfo2( ).
    CALL FUNCTION 'ICM_GET_INFO2'
      IMPORTING
        info_data   = icm_info_data
      TABLES
        servlist    = dummy_icm_servlist2
*       THRLIST     = ICM_THRLIST
*       SERVLIST3   = ICM_SERVLIST
      EXCEPTIONS
        icm_error   = 1
        icm_timeout = 2
        OTHERS      = 6.
    IF sy-subrc <> 0.
      " TODO
    ENDIF.
    result = icm_info_data-trace_lvl.
  ENDMETHOD.


  METHOD set_trace_level.
    " Credit: subroutine ICMAN_SET_PARAM in RSMONICM.
    DATA p_name  TYPE pfeparname VALUE 'rdisp/TRACE'.
    DATA rc TYPE sysubrc.

    DATA(p_value) = CONV pfepvalue( value ).
    CALL 'ThSysInfo'                                      "#EC CI_CCALL
         ID 'OPCODE'    FIELD lif_tskhincl=>opcode_icm
         ID 'ICMOPCODE' FIELD lif_icmdef=>dp_plugin_op_chng_param
         ID 'PNAME'     FIELD p_name
         ID 'PVALUE'    FIELD p_value.
    IF sy-subrc <> 0.
      " TODO replace with exception
      CASE sy-subrc.
*      WHEN lif_icmdef=>icmeok.
*        MESSAGE s005(icm).
        WHEN lif_icmdef=>icmenotavail.
          MESSAGE i032(icm).
        WHEN OTHERS.
          MESSAGE e006(icm) WITH rc.
      ENDCASE.
    ENDIF.
  ENDMETHOD.
ENDCLASS.


CLASS zcl_certi_strust DEFINITION
  FINAL
  CREATE PUBLIC .

************************************************************************
* Trust Management
*
* Copyright 2021 Marc Bernard <https://marcbernardtools.com/>
* SPDX-License-Identifier: MIT
************************************************************************
  PUBLIC SECTION.

    CONSTANTS c_version TYPE string VALUE '1.0.0' ##NEEDED.

    TYPES:
      ty_line        TYPE c LENGTH 80,
      ty_certificate TYPE STANDARD TABLE OF ty_line WITH DEFAULT KEY,
      BEGIN OF ty_certattr,
        subject     TYPE string,
        issuer      TYPE string,
        serialno    TYPE string,
        validfrom   TYPE string,
        validto     TYPE string,
        datefrom    TYPE d,
        dateto      TYPE d,
        certificate TYPE xstring,
      END OF ty_certattr,
      ty_certattr_tt TYPE STANDARD TABLE OF ty_certattr WITH DEFAULT KEY.

    METHODS constructor
      IMPORTING
        !iv_context TYPE psecontext
        !iv_applic  TYPE ssfappl
      RAISING
        zcx_certi_strust.

    METHODS load
      IMPORTING
        !iv_create TYPE abap_bool DEFAULT abap_false
        !iv_id     TYPE ssfid OPTIONAL
        !iv_org    TYPE string OPTIONAL
      RAISING
        zcx_certi_strust.

    METHODS add
      IMPORTING
        !it_certificate TYPE ty_certificate
      RAISING
        zcx_certi_strust.

    METHODS get_own_certificate
      RETURNING
        VALUE(rs_result) TYPE ty_certattr
      RAISING
        zcx_certi_strust.

    METHODS get_certificate_list
      RETURNING
        VALUE(rt_result) TYPE ty_certattr_tt
      RAISING
        zcx_certi_strust.

    METHODS remove
      IMPORTING
        VALUE(iv_subject) TYPE string
      RAISING
        zcx_certi_strust.

    METHODS update
      RETURNING
        VALUE(rt_result) TYPE ty_certattr_tt
      RAISING
        zcx_certi_strust.

  PROTECTED SECTION.
  PRIVATE SECTION.

    DATA:
      mv_context   TYPE psecontext,
      mv_applic    TYPE ssfappl,
      mv_psename   TYPE ssfpsename,
      mv_psetext   TYPE strustappltxt ##NEEDED,
      mv_distrib   TYPE ssfflag,
      mv_tempfile  TYPE localfile,
      mv_id        TYPE ssfid,
      mv_profile   TYPE ssfpab,
      mv_profilepw TYPE ssfpabpw,
      mv_cert_own  TYPE xstring,
      mt_cert_new  TYPE ty_certattr_tt,
      ms_cert_old  TYPE ty_certattr,
      mt_cert_old  TYPE ty_certattr_tt,
      mv_save      TYPE abap_bool.

    METHODS _create
      IMPORTING
        !iv_id  TYPE ssfid OPTIONAL
        !iv_org TYPE string OPTIONAL
      RAISING
        zcx_certi_strust.

    METHODS _lock
      RAISING
        zcx_certi_strust.

    METHODS _unlock
      RAISING
        zcx_certi_strust.

    METHODS _save
      RAISING
        zcx_certi_strust.

ENDCLASS.



CLASS zcl_certi_strust IMPLEMENTATION.


  METHOD add.

    DATA:
      lv_certb64  TYPE string,
      lo_certobj  TYPE REF TO cl_abap_x509_certificate,
      ls_cert_new TYPE ty_certattr.

    FIELD-SYMBOLS:
      <lv_data> TYPE any.

    CONCATENATE LINES OF it_certificate INTO lv_certb64.

    " Remove Header and Footer
    TRY.
        FIND REGEX '-{5}.{0,}BEGIN.{0,}-{5}(.*)-{5}.{0,}END.{0,}-{5}' IN lv_certb64 SUBMATCHES lv_certb64.
        IF sy-subrc = 0.
          ASSIGN lv_certb64 TO <lv_data>.
          ASSERT sy-subrc = 0.
        ELSE.
          zcx_certi_strust=>raise( 'Inconsistent certificate format'(010) ).
        ENDIF.
      CATCH cx_sy_regex_too_complex.
        " e.g. multiple PEM frames in file
        zcx_certi_strust=>raise( 'Inconsistent certificate format'(010) ).
    ENDTRY.

    TRY.
        CREATE OBJECT lo_certobj
          EXPORTING
            if_certificate = <lv_data>.

        ls_cert_new-certificate = lo_certobj->get_certificate( ).

        CALL FUNCTION 'SSFC_PARSE_CERTIFICATE'
          EXPORTING
            certificate         = ls_cert_new-certificate
          IMPORTING
            subject             = ls_cert_new-subject
            issuer              = ls_cert_new-issuer
            serialno            = ls_cert_new-serialno
            validfrom           = ls_cert_new-validfrom
            validto             = ls_cert_new-validto
          EXCEPTIONS
            ssf_krn_error       = 1
            ssf_krn_nomemory    = 2
            ssf_krn_nossflib    = 3
            ssf_krn_invalid_par = 4
            OTHERS              = 5.
        IF sy-subrc <> 0.
          _unlock( ).
          zcx_certi_strust=>raise_t100( ).
        ENDIF.

        ls_cert_new-datefrom = ls_cert_new-validfrom(8).
        ls_cert_new-dateto   = ls_cert_new-validto(8).
        APPEND ls_cert_new TO mt_cert_new.

      CATCH cx_abap_x509_certificate.
        _unlock( ).
        zcx_certi_strust=>raise_t100( ).
    ENDTRY.

  ENDMETHOD.


  METHOD constructor.

    mv_context = iv_context.
    mv_applic  = iv_applic.

    CALL FUNCTION 'SSFPSE_FILENAME'
      EXPORTING
        context       = mv_context
        applic        = mv_applic
      IMPORTING
        psename       = mv_psename
        psetext       = mv_psetext
        distrib       = mv_distrib
      EXCEPTIONS
        pse_not_found = 1
        OTHERS        = 2.
    IF sy-subrc <> 0.
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

  ENDMETHOD.


  METHOD get_certificate_list.

    DATA:
      lt_certlist TYPE ssfbintab,
      ls_cert_old TYPE ty_certattr.

    FIELD-SYMBOLS <lv_certlist> LIKE LINE OF lt_certlist.

    CALL FUNCTION 'SSFC_GET_CERTIFICATELIST'
      EXPORTING
        profile               = mv_profile
        profilepw             = mv_profilepw
      IMPORTING
        certificatelist       = lt_certlist
      EXCEPTIONS
        ssf_krn_error         = 1
        ssf_krn_nomemory      = 2
        ssf_krn_nossflib      = 3
        ssf_krn_invalid_par   = 4
        ssf_krn_nocertificate = 5
        OTHERS                = 6.
    IF sy-subrc <> 0.
      _unlock( ).
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

    LOOP AT lt_certlist ASSIGNING <lv_certlist>.

      CLEAR ls_cert_old.

      CALL FUNCTION 'SSFC_PARSE_CERTIFICATE'
        EXPORTING
          certificate         = <lv_certlist>
        IMPORTING
          subject             = ls_cert_old-subject
          issuer              = ls_cert_old-issuer
          serialno            = ls_cert_old-serialno
          validfrom           = ls_cert_old-validfrom
          validto             = ls_cert_old-validto
        EXCEPTIONS
          ssf_krn_error       = 1
          ssf_krn_nomemory    = 2
          ssf_krn_nossflib    = 3
          ssf_krn_invalid_par = 4
          OTHERS              = 5.
      IF sy-subrc <> 0.
        _unlock( ).
        zcx_certi_strust=>raise_t100( ).
      ENDIF.

      ls_cert_old-datefrom = ls_cert_old-validfrom(8).
      ls_cert_old-dateto   = ls_cert_old-validto(8).
      APPEND ls_cert_old TO mt_cert_old.

    ENDLOOP.

    rt_result = mt_cert_old.

  ENDMETHOD.


  METHOD get_own_certificate.

    mv_profile = mv_tempfile.

    CALL FUNCTION 'SSFC_GET_OWNCERTIFICATE'
      EXPORTING
        profile               = mv_profile
        profilepw             = mv_profilepw
      IMPORTING
        certificate           = mv_cert_own
      EXCEPTIONS
        ssf_krn_error         = 1
        ssf_krn_nomemory      = 2
        ssf_krn_nossflib      = 3
        ssf_krn_invalid_par   = 4
        ssf_krn_nocertificate = 5
        OTHERS                = 6.
    IF sy-subrc <> 0.
      _unlock( ).
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

    CALL FUNCTION 'SSFC_PARSE_CERTIFICATE'
      EXPORTING
        certificate         = mv_cert_own
      IMPORTING
        subject             = ms_cert_old-subject
        issuer              = ms_cert_old-issuer
        serialno            = ms_cert_old-serialno
        validfrom           = ms_cert_old-validfrom
        validto             = ms_cert_old-validto
      EXCEPTIONS
        ssf_krn_error       = 1
        ssf_krn_nomemory    = 2
        ssf_krn_nossflib    = 3
        ssf_krn_invalid_par = 4
        OTHERS              = 5.
    IF sy-subrc <> 0.
      _unlock( ).
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

    ms_cert_old-datefrom = ms_cert_old-validfrom(8).
    ms_cert_old-dateto   = ms_cert_old-validto(8).

    rs_result = ms_cert_old.

  ENDMETHOD.


  METHOD load.

    CLEAR mv_save.

    _lock( ).

    CALL FUNCTION 'SSFPSE_LOAD'
      EXPORTING
        psename           = mv_psename
      IMPORTING
        id                = mv_id
        fname             = mv_tempfile
      EXCEPTIONS
        authority_missing = 1
        database_failed   = 2
        OTHERS            = 3.
    IF sy-subrc <> 0.
      IF iv_create = abap_true.
        _create(
          iv_id  = iv_id
          iv_org = iv_org ).
      ELSE.
        zcx_certi_strust=>raise_t100( ).
      ENDIF.
    ENDIF.

  ENDMETHOD.


  METHOD remove.

    FIELD-SYMBOLS:
      <ls_cert_old> LIKE LINE OF mt_cert_old.

    " Remove certificate
    LOOP AT mt_cert_old ASSIGNING <ls_cert_old> WHERE subject = iv_subject.

      CALL FUNCTION 'SSFC_REMOVECERTIFICATE'
        EXPORTING
          profile               = mv_profile
          profilepw             = mv_profilepw
          subject               = <ls_cert_old>-subject
          issuer                = <ls_cert_old>-issuer
          serialno              = <ls_cert_old>-serialno
        EXCEPTIONS
          ssf_krn_error         = 1
          ssf_krn_nomemory      = 2
          ssf_krn_nossflib      = 3
          ssf_krn_invalid_par   = 4
          ssf_krn_nocertificate = 5
          OTHERS                = 6.
      IF sy-subrc <> 0.
        _unlock( ).
        zcx_certi_strust=>raise_t100( ).
      ENDIF.

      mv_save = abap_true.
    ENDLOOP.

    _save( ).

    _unlock( ).

  ENDMETHOD.


  METHOD update.

    FIELD-SYMBOLS:
      <ls_cert_old> LIKE LINE OF mt_cert_old,
      <ls_cert_new> LIKE LINE OF mt_cert_new.

    " Remove expired certificates
    LOOP AT mt_cert_old ASSIGNING <ls_cert_old>.

      LOOP AT mt_cert_new ASSIGNING <ls_cert_new> WHERE subject = <ls_cert_old>-subject.

        IF <ls_cert_new>-dateto > <ls_cert_old>-dateto.
          " Certificate is newer, so remove the old certificate
          CALL FUNCTION 'SSFC_REMOVECERTIFICATE'
            EXPORTING
              profile               = mv_profile
              profilepw             = mv_profilepw
              subject               = <ls_cert_old>-subject
              issuer                = <ls_cert_old>-issuer
              serialno              = <ls_cert_old>-serialno
            EXCEPTIONS
              ssf_krn_error         = 1
              ssf_krn_nomemory      = 2
              ssf_krn_nossflib      = 3
              ssf_krn_invalid_par   = 4
              ssf_krn_nocertificate = 5
              OTHERS                = 6.
          IF sy-subrc <> 0.
            _unlock( ).
            zcx_certi_strust=>raise_t100( ).
          ENDIF.

          mv_save = abap_true.
        ELSE.
          " Certificate already exists, no update necessary
          DELETE mt_cert_new.
        ENDIF.

      ENDLOOP.

    ENDLOOP.

    " Add new certificates to PSE
    LOOP AT mt_cert_new ASSIGNING <ls_cert_new>.

      CALL FUNCTION 'SSFC_PUT_CERTIFICATE'
        EXPORTING
          profile             = mv_profile
          profilepw           = mv_profilepw
          certificate         = <ls_cert_new>-certificate
        EXCEPTIONS
          ssf_krn_error       = 1
          ssf_krn_nomemory    = 2
          ssf_krn_nossflib    = 3
          ssf_krn_invalid_par = 4
          ssf_krn_certexists  = 5
          OTHERS              = 6.
      IF sy-subrc <> 0.
        _unlock( ).
        zcx_certi_strust=>raise_t100( ).
      ENDIF.

      mv_save = abap_true.
    ENDLOOP.

    _save( ).

    _unlock( ).

    rt_result = mt_cert_new.

  ENDMETHOD.


  METHOD _create.

    DATA:
      lv_license_num TYPE c LENGTH 10,
      lv_id          TYPE ssfid,
      lv_subject     TYPE certsubjct,
      lv_psepath     TYPE trfile.

*   Create new PSE (using RSA-SHA256 2048 which is the default in STRUST in recent releases)
    IF iv_id IS INITIAL.
      CASE mv_applic.
        WHEN 'DFAULT'.
          lv_id = `CN=%SID SSL client SSL Client (Standard), ` &&
                  `OU=I%LIC, OU=SAP Web AS, O=SAP Trust Community, C=DE` ##NO_TEXT.
        WHEN 'ANONYM'.
          lv_id = 'CN=anonymous' ##NO_TEXT.
      ENDCASE.
    ELSE.
      lv_id = iv_id.
    ENDIF.

    CALL FUNCTION 'SLIC_GET_LICENCE_NUMBER'
      IMPORTING
        license_number = lv_license_num.

    REPLACE '%SID' WITH sy-sysid INTO lv_id.
    REPLACE '%LIC' WITH lv_license_num INTO lv_id.
    REPLACE '%ORG' WITH iv_org INTO lv_id.
    CONDENSE lv_id.

    lv_subject = lv_id.

    CALL FUNCTION 'SSFPSE_CREATE'
      EXPORTING
        dn                = lv_subject
        alg               = 'R'
        keylen            = 2048
      IMPORTING
        psepath           = lv_psepath
      EXCEPTIONS
        ssf_unknown_error = 1
        OTHERS            = 2.
    IF sy-subrc <> 0.
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

    mv_tempfile = lv_psepath.

    _save( ).

  ENDMETHOD.


  METHOD _lock.

    CALL FUNCTION 'SSFPSE_ENQUEUE'
      EXPORTING
        psename         = mv_psename
      EXCEPTIONS
        database_failed = 1
        foreign_lock    = 2
        internal_error  = 3
        OTHERS          = 4.
    IF sy-subrc <> 0.
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

  ENDMETHOD.


  METHOD _save.

    DATA lv_credname TYPE icm_credname.

    CHECK mv_save = abap_true.

    " Store PSE
    CALL FUNCTION 'SSFPSE_STORE'
      EXPORTING
        fname             = mv_tempfile
        psepin            = mv_profilepw
        psename           = mv_psename
        id                = mv_id
        b_newdn           = abap_false
        b_distribute      = mv_distrib
      EXCEPTIONS
        file_load_failed  = 1
        storing_failed    = 2
        authority_missing = 3
        OTHERS            = 4.
    IF sy-subrc <> 0.
      _unlock( ).
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

    lv_credname = mv_psename.

    CALL FUNCTION 'ICM_SSL_PSE_CHANGED'
      EXPORTING
        global              = 1
        cred_name           = lv_credname
      EXCEPTIONS
        icm_op_failed       = 1
        icm_get_serv_failed = 2
        icm_auth_failed     = 3
        OTHERS              = 4.
    IF sy-subrc = 0.
      MESSAGE s086(trust).
    ELSE.
      MESSAGE s085(trust).
    ENDIF.

  ENDMETHOD.



  METHOD _unlock.

    " Drop temporary file
    TRY.
        DELETE DATASET mv_tempfile.
      CATCH cx_sy_file_open.
        zcx_certi_strust=>raise( 'Error deleting file'(020) && | { mv_tempfile }| ).
      CATCH cx_sy_file_authority.
        zcx_certi_strust=>raise( 'Not authorized to delete file'(030) && | { mv_tempfile }| ).
    ENDTRY.

    " Unlock PSE
    CALL FUNCTION 'SSFPSE_DEQUEUE'
      EXPORTING
        psename         = mv_psename
      EXCEPTIONS
        database_failed = 1
        foreign_lock    = 2
        internal_error  = 3
        OTHERS          = 4.
    IF sy-subrc <> 0.
      zcx_certi_strust=>raise_t100( ).
    ENDIF.

  ENDMETHOD.
ENDCLASS.
**********************************************************************
* End of include from https://github.com/sandraros/zcerti
**********************************************************************

*--------------------------------------------------------------------*
CLASS sslcert DEFINITION.
*--------------------------------------------------------------------*

  PUBLIC SECTION.
    METHODS constructor.
    METHODS execute IMPORTING host TYPE string.
    METHODS exists  IMPORTING host          TYPE string
                    RETURNING VALUE(result) TYPE abap_bool.

  PROTECTED SECTION.
  PRIVATE SECTION.
*    CONSTANTS host TYPE string VALUE `github.com`.
    DATA: strust TYPE REF TO zcl_certi_strust.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS sslcert IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD execute.

    DATA strust_error TYPE REF TO zcx_certi_strust.

    IF exists( host ).
      out->write( |Certificate for { host } already exists, not imported| ).
      RETURN.
    ENDIF.

    DATA(icm_trace_api) = zcl_certi_icm_trace=>create( ).

    " Get current ICM trace level for later restore
    DATA(original_trace_level) = icm_trace_api->get_trace_level( ).

    " Set the ICM trace level to 3 to obtain the contents of certificates
    icm_trace_api->set_trace_level( '3' ).

    " Clear the trace
    icm_trace_api->delete_trace( ).

    "===================================
    " HTTPS GET
    "===================================
    DATA http_client TYPE REF TO if_http_client.
*  cl_http_client=>create_by_destination( EXPORTING  destination = 'RFC_DESTINATION'
*                                         IMPORTING  client      = lo_http_client
*                                         EXCEPTIONS OTHERS      = 1 ).
    cl_http_client=>create_by_url( EXPORTING  url    = `https://` && host
                                   IMPORTING  client = http_client
                                   EXCEPTIONS OTHERS = 1 ).

    DATA request TYPE REF TO if_http_request.
    request = http_client->request.
    request->set_method( 'GET' ).
    request->set_version( if_http_request=>co_protocol_version_1_1 ). " HTTP 1.0 or 1.1
    http_client->send( EXCEPTIONS OTHERS = 1 ).
    DATA return_code TYPE i.
    DATA content     TYPE string.
    DATA: reason TYPE string.
    http_client->receive( EXCEPTIONS OTHERS = 1 ).
    http_client->response->get_status( IMPORTING code = return_code reason = reason ).
    IF return_code <> 200 AND return_code <> 500.
      out->write( |Could not reach host { host }, returned { return_code }| ).
      RETURN.
    ENDIF.
    content = http_client->response->get_cdata( ).
    http_client->close( EXCEPTIONS OTHERS = 1 ).

    " Get and parse the ICM trace
    DATA(parsed_icm_trace) = icm_trace_api->get_parsed_trace( ).

    " Restore original ICM trace level
    icm_trace_api->set_trace_level( original_trace_level ).

    TRY.
        LOOP AT parsed_icm_trace-certificates REFERENCE INTO DATA(certificate).
          strust->add( CONV #( certificate->lines ) ).
        ENDLOOP.
        strust->update( ).
        COMMIT WORK.
        out->write( |Certificate for { host } imported| ).

      CATCH zcx_certi_strust INTO strust_error.
        MESSAGE strust_error TYPE 'I' DISPLAY LIKE 'E'.
        RETURN.
    ENDTRY.

  ENDMETHOD.


  METHOD exists.

    TRY.

        " initialize MV_PROFILE from MV_TEMPFILE
        strust->get_own_certificate( ).
        " get list only after MV_PROFILE is initialized
        DATA(certificates) = strust->get_certificate_list( ).

        LOOP AT certificates TRANSPORTING NO FIELDS WHERE subject CS host.
        ENDLOOP.
        IF sy-subrc = 0.
          result = abap_true.
        ENDIF.

      CATCH zcx_certi_strust INTO DATA(error).
        out->write( 'SSL existence check failed' ).
    ENDTRY.

  ENDMETHOD.


  METHOD constructor.

    TRY.

        strust = NEW zcl_certi_strust( iv_context = 'SSLC'
                                       iv_applic  = 'ANONYM' ).
        strust->load( ).

      CATCH zcx_certi_strust INTO DATA(error).
        out->write( |zcl_certi_strust error: { error->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS main DEFINITION CREATE PUBLIC.
*--------------------------------------------------------------------*

  PUBLIC SECTION.
    METHODS run.
    METHODS constructor.
  PROTECTED SECTION.
  PRIVATE SECTION.
    TYPES: BEGIN OF t_repo,
             name    TYPE string,
             package TYPE devclass,
             url     TYPE string,
           END OF t_repo.

    DATA repos TYPE STANDARD TABLE OF t_repo WITH EMPTY KEY.
    DATA user  TYPE rfcalias.
    DATA token TYPE rfcexec_ext.
    METHODS import_repos.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS main IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD constructor.

    user = p_user.
    token = p_token.

    "Customize setup here, or copy/paste into include zdevsysinit_params
    "Create include outside package (e.g. $tmp) if it should not go to GitHub
    "Remember to back it up locally!
    repos = VALUE #(
        ( name = `` package = '' url = `` )
     ).

    INCLUDE zdevsysinit_params IF FOUND.

  ENDMETHOD.


  METHOD run.

    IF p_rfcdst = abap_true.
      out->write( `Creating RFC Destination` ).
      NEW rfc_destination( )->execute(
        i_name  = 'GITHUB'
        i_user  = user
        i_token = token ).
    ENDIF.

    IF p_certi = abap_true.
      out->write( `Creating Certificates` ).
      DATA(cert) = NEW sslcert( ).
      cert->execute( `github.com` ).
      cert->execute( `github.io` ).
    ENDIF.

    IF p_abapgt = abap_true.
      out->write( `Creating abapGit` ).
      TRY.
          NEW ag_standalone( )->execute( ).
        CATCH lcx_error.
          out->write( `Could not create ZABAPGIT_STANDALONE` ).
      ENDTRY.
    ENDIF.

    IF p_repos = abap_true.
      out->write( `Importing repos` ).
      import_repos( ).
    ENDIF.

  ENDMETHOD.


  METHOD import_repos.

    TRY.
        DATA(repo_importer) = NEW repo( ).
      CATCH zcx_abapgit_exception INTO DATA(error).
        out->write( |Could not get list of repos: { error->get_text( ) }| ).
    ENDTRY.

    LOOP AT repos REFERENCE INTO DATA(repo).

      repo_importer->setup(
        i_name    = repo->name
        i_package = repo->package
        i_url     = repo->url ).

    ENDLOOP.


  ENDMETHOD.


ENDCLASS.


*--------------------------------------------------------------------*
INITIALIZATION.
*--------------------------------------------------------------------*
  DATA dummy TYPE string.

  out = cl_demo_output=>new( ).

  IF NOT rfc_destination=>exists( 'GITHUB' ).
    p_rfcdst = abap_true.
  ENDIF.

  IF NOT NEW sslcert( )->exists( `github.com` ).
    p_certi = abap_true.
  ENDIF.

  SELECT SINGLE progname FROM reposrc INTO dummy
        WHERE progname = 'ZABAPGIT_STANDALONE'.
  p_abapgt = boolc( sy-subrc <> 0 ).


*--------------------------------------------------------------------*
START-OF-SELECTION.
*--------------------------------------------------------------------*

  NEW main( )->run( ).
  out->display( ).


**********************************************************************
* Tests
**********************************************************************

*--------------------------------------------------------------------*
CLASS ltc_rfcdest DEFINITION FINAL FOR TESTING
  INHERITING FROM rfc_destination
  DURATION SHORT
  RISK LEVEL HARMLESS.
*--------------------------------------------------------------------*

  PROTECTED SECTION.
    METHODS create_rfc_destination REDEFINITION.
    METHODS delete_rfc_destination REDEFINITION.
    METHODS check_existence REDEFINITION.

  PRIVATE SECTION.
    DATA: created   TYPE abap_bool,
          deleted   TYPE abap_bool,
          td_exists TYPE abap_bool.

    METHODS create_if_not_exists FOR TESTING RAISING cx_static_check.
    METHODS no_create_if_exists FOR TESTING RAISING cx_static_check.
    METHODS recreate_if_reset FOR TESTING RAISING cx_static_check.
    METHODS setup.

ENDCLASS.


*--------------------------------------------------------------------*
CLASS ltc_rfcdest IMPLEMENTATION.
*--------------------------------------------------------------------*

  METHOD setup.
    out = cl_demo_output=>new( ).
  ENDMETHOD.

  METHOD create_if_not_exists.

    td_exists = abap_false.

    execute(
      i_name  = ''
      i_user  = ''
      i_token = ''
    ).

    cl_abap_unit_assert=>assert_true( created ).

  ENDMETHOD.


  METHOD no_create_if_exists.
    td_exists = abap_true.
    execute(
      i_name  = ''
      i_user  = ''
      i_token = ''
    ).
    cl_abap_unit_assert=>assert_false( created ).
  ENDMETHOD.


  METHOD recreate_if_reset.
    td_exists = abap_true.
    execute(
      i_name  = ''
      i_user  = ''
      i_token = ''
      i_reset = abap_true
    ).
    cl_abap_unit_assert=>assert_true( deleted ).
    cl_abap_unit_assert=>assert_true( created ).
  ENDMETHOD.


  METHOD create_rfc_destination.
    created = abap_true.
  ENDMETHOD.


  METHOD delete_rfc_destination.
    deleted = abap_true.
  ENDMETHOD.


  METHOD check_existence.
    result = td_exists.
  ENDMETHOD.


ENDCLASS.