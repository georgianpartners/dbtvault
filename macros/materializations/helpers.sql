{#-- Helper macros for custom materializations #}

{#-- MULTI-DISPATCH MACROS #}

{#-- REPLACE_PLACEHOLDER_WITH_FILTER #}

{%- macro replace_placeholder_with_filter(core_sql, timestamp_field, start_timestamp, stop_timestamp, offset, period) -%}
    {# BQ Change: Look locally cause of incompatible macro definitions #}
    {% set macro = adapter.dispatch('replace_placeholder_with_filter')(
        core_sql=core_sql,
        timestamp_field=timestamp_field,
        start_timestamp=start_timestamp,
        stop_timestamp=stop_timestamp,
        offset=offset,
        period=period) %}
    {% do return(macro) %}
{%- endmacro %}

{% macro snowflake__replace_placeholder_with_filter(core_sql, timestamp_field, start_timestamp, stop_timestamp, offset, period) %}
    {%- set period_filter -%}
            (TO_DATE({{ timestamp_field }}) >= DATE_TRUNC('{{ period }}', TO_DATE('{{ start_timestamp }}') + INTERVAL '{{ offset }} {{ period }}') AND
             TO_DATE({{ timestamp_field }}) < DATE_TRUNC('{{ period }}', TO_DATE('{{ start_timestamp }}') + INTERVAL '{{ offset }} {{ period }}' + INTERVAL '1 {{ period }}'))
      AND (TO_DATE({{ timestamp_field }}) >= TO_DATE('{{ start_timestamp }}'))
    {%- endset -%}

    {%- set filtered_sql = core_sql | replace("__PERIOD_FILTER__", period_filter) -%}

    {% do return(filtered_sql) %}
{% endmacro %}


{# BQ Change: Added BQ implementaion #}
{% macro bigquery__replace_placeholder_with_filter(core_sql, timestamp_field, start_timestamp, stop_timestamp, offset, period) %}

    {%- set period_filter -%}
            {# BQ Change: TO_DATE() -> Date(), reorder date_trunc args and use DATE_ADD instead of + #}
            (DATE({{ timestamp_field }}) >= DATE_TRUNC(DATE_ADD(DATE('{{ start_timestamp }}'), INTERVAL '{{ offset }} {{ period }}'), '{{ period }}') AND
             DATE({{ timestamp_field }}) < DATE_TRUNC(DATE_ADD(DATE('{{ start_timestamp }}'), INTERVAL '{{ offset + 1 }} {{ period }}'), '{{ period }}'))
      AND (DATE({{ timestamp_field }}) >= DATE('{{ start_timestamp }}'))
    {%- endset -%}

    {%- set filtered_sql = core_sql | replace("__PERIOD_FILTER__", period_filter) -%}

    {% do return(filtered_sql) %}
{% endmacro %}


{#-- GET_PERIOD_FILTER_SQL #}

{%- macro get_period_filter_sql(target_cols_csv, base_sql, timestamp_field, period, start_timestamp, stop_timestamp, offset) -%}
    {# BQ Change: Look locally cause of incompatible macro definitions #}
    {% set macro = adapter.dispatch('get_period_filter_sql')(
        target_cols_csv=target_cols_csv,
        base_sql=base_sql,
        timestamp_field=timestamp_field,
        period=period,
        start_timestamp=start_timestamp,
        stop_timestamp=stop_timestamp,
        offset=offset
      ) %}
    {% do return(macro) %}
{%- endmacro %}

{# BQ Change: Snowflake__ to bigquery__ #}
{% macro bigquery__get_period_filter_sql(target_cols_csv, base_sql, timestamp_field, period, start_timestamp, stop_timestamp, offset) -%}

    {%- set filtered_sql = {'sql': base_sql} -%}

    {%- do filtered_sql.update({'sql': dbtvault_bq.replace_placeholder_with_filter(filtered_sql.sql,
                                                                                timestamp_field,
                                                                                start_timestamp,
                                                                                stop_timestamp,
                                                                                offset, period)}) -%}
    select {{ target_cols_csv }} from ({{ filtered_sql.sql }})
{%- endmacro %}


{#-- GET_PERIOD_BOUNDARIES #}

{%- macro get_period_boundaries(target_schema, target_table, timestamp_field, start_date, stop_date, period) -%}
    {# BQ Change: Look locally cause of incompatible macro definitions #}
    {% set macro = adapter.dispatch('get_period_boundaries')(
        target_schema=target_schema,
        target_table=target_table,
        timestamp_field=timestamp_field,
        start_date=start_date,
        stop_date=stop_date,
        period=period
      ) %}

    {% do return(macro) %}
{%- endmacro %}


{% macro snowflake__get_period_boundaries(target_schema, target_table, timestamp_field, start_date, stop_date, period) -%}

    {% set period_boundary_sql -%}
        with data as (
            select
                coalesce(max({{ timestamp_field }}), '{{ start_date }}')::timestamp as start_timestamp,
                coalesce({{ dbt_utils.dateadd('millisecond', 86399999, "nullif('" ~ stop_date ~ "','')::timestamp") }},
                         {{ dbt_utils.current_timestamp() }} ) as stop_timestamp
            from {{ target_schema }}.{{ target_table }}
        )
        select
            start_timestamp,
            stop_timestamp,
            {{ dbt_utils.datediff('start_timestamp',
                                  'stop_timestamp',
                                  period) }} + 1 as num_periods
        from data
    {%- endset %}

    {% set period_boundaries_dict = dbt_utils.get_query_results_as_dict(period_boundary_sql) %}

    {% set period_boundaries = {'start_timestamp': period_boundaries_dict['START_TIMESTAMP'][0] | string,
                                'stop_timestamp': period_boundaries_dict['STOP_TIMESTAMP'][0] | string,
                                'num_periods': period_boundaries_dict['NUM_PERIODS'][0] | int} %}

    {% do return(period_boundaries) %}
{%- endmacro %}

{# BQ Change: Added BQ implementation #}
{% macro bigquery__get_period_boundaries(target_schema, target_table, timestamp_field, start_date, stop_date, period) -%}

    {% set period_boundary_sql -%}
        with data as (
            select
                {# BQ Change: timestamp conversion #}
                TIMESTAMP(coalesce(max({{ timestamp_field }}), '{{ start_date }}')) as start_timestamp,
                coalesce({{ dbt_utils.dateadd('millisecond', 86399999, "TIMESTAMP(nullif('" ~ stop_date ~ "',''))") }},
                         {{ dbt_utils.current_timestamp() }} ) as stop_timestamp
            from {{ target_schema }}.{{ target_table }}
        )
        select
            start_timestamp,
            stop_timestamp,
            {{ dbt_utils.datediff('start_timestamp',
                                  'stop_timestamp',
                                  period) }} + 1 as num_periods
        from data
    {%- endset %}

    {% set period_boundaries_dict = dbt_utils.get_query_results_as_dict(period_boundary_sql) %}

    {% set period_boundaries = {'start_timestamp': period_boundaries_dict['START_TIMESTAMP'][0] | string,
                                'stop_timestamp': period_boundaries_dict['STOP_TIMESTAMP'][0] | string,
                                'num_periods': period_boundaries_dict['NUM_PERIODS'][0] | int} %}

    {% do return(period_boundaries) %}
{%- endmacro %}


{#-- GET_PERIOD_OF_LOAD #}

{%- macro get_period_of_load(period, offset, start_timestamp) -%}
    {# BQ Change: Look locally cause of incompatible macro definitions #}
    {% set macro = adapter.dispatch('get_period_of_load')(
        period=period,
        offset=offset,
        start_timestamp=start_timestamp
      ) %}

    {% do return(macro) %}
{%- endmacro %}


{%- macro snowflake__get_period_of_load(period, offset, start_timestamp) -%}

    {% set period_of_load_sql -%}
        SELECT DATE_TRUNC('{{ period }}', DATEADD({{ period }}, {{ offset }}, TO_DATE('{{start_timestamp}}'))) AS period_of_load #}
    {%- endset %}

    {% set period_of_load_dict = dbt_utils.get_query_results_as_dict(period_of_load_sql) %}

    {% set period_of_load = period_of_load_dict['PERIOD_OF_LOAD'][0] | string %}

    {% do return(period_of_load) %}
{%- endmacro -%}

{# BQ Change: Added BQ implementation #}
{%- macro bigquery__get_period_of_load(period, offset, start_timestamp) -%}

    {% set period_of_load_sql -%}
        {# BQ Change: compatible date logic #}
        SELECT DATE_TRUNC(DATEADD(DATE('{{start_timestamp}}'), INTERVAL {{ offset }} {{ period }}), '{{ period }}') AS period_of_load
    {%- endset %}

    {% set period_of_load_dict = dbt_utils.get_query_results_as_dict(period_of_load_sql) %}

    {% set period_of_load = period_of_load_dict['PERIOD_OF_LOAD'][0] | string %}

    {% do return(period_of_load) %}
{%- endmacro -%}


{#-- OTHER MACROS #}

{% macro is_vault_insert_by_period() %}
    {#-- do not run introspective queries in parsing #}
    {% if not execute %}
        {{ return(False) }}
    {% else %}
        {% set relation = adapter.get_relation(this.database, this.schema, this.table) %}

            {{ return(relation is not none
                      and relation.type == 'table'
                      and model.config.materialized == 'vault_insert_by_period'
                      and not flags.FULL_REFRESH) }}
    {% endif %}
{% endmacro %}
