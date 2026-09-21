{#-
    Divides one expression by another and returns null instead of failing when the
    divisor is zero, which ANSI mode would otherwise raise as an error.
-#}
{% macro safe_divide(numerator, denominator) -%}
    ({{ numerator }}) / nullif(({{ denominator }}), 0)
{%- endmacro %}
