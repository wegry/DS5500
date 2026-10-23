-- One row per ComStock model x census tract x package upgrade x measure, with the quantity
-- each measure is costed on. Quantity is 0 where the measure does not apply to the model.
-- Sizes come from the upgraded model, so new heat pumps carry their upgraded capacity.
{%- set m2_to_sqft = 10.7639 %}
{%- set measures = {
    "exterior_wall_insulation": ('"out.params.ext_wall_area..m2" * ' ~ m2_to_sqft, "sqft"),
    "roof_insulation_aedg": ('"out.params.ext_roof_area..m2" * ' ~ m2_to_sqft, "sqft"),
    "env_new_aedg_windows": ('"out.params.ext_window_area..m2" * ' ~ m2_to_sqft, "sqft"),
    "light_led": ('"in.sqft..ft2" * "out.params.interior_lighting_power_density..w_per_ft2"', "W"),
    "add_heat_pump_rtu": ('"out.params.dx_cooling_capacity_tons..tons"', "ton"),
    "replace_boiler_by_heatpump": ('"out.params.ww_hp_heating_capacity..kbtu_per_hr" / 12', "ton"),
} %}
with raw as (
    select *
    from read_parquet([
        {%- for i in var("package_upgrade_ids") %}
        '{{ var("comstock_full_dir") }}/{{ var("comstock_county_prefix") }}_upgrade{{ i }}.parquet'{{ "," if not loop.last }}
        {%- endfor %}
    ], union_by_name = true)
)

{% for measure, spec in measures.items() -%}
select
    bldg_id || '-' || "in.nhgis_tract_gisjoin" || '-' || upgrade || '-' || '{{ measure }}'
        as comstock_measure_key,
    bldg_id as comstock_id,
    upgrade as upgrade_id,
    weight,
    "in.sqft..ft2" as gfa_sqft,
    '{{ measure }}' as measure,
    coalesce("applicability.{{ measure }}", false) as applicability,
    case when "applicability.{{ measure }}" then coalesce({{ spec[0] }}, 0) else 0 end
        as quantity,
    '{{ spec[1] }}' as quantity_unit
from raw
{{ "union all" if not loop.last }}
{% endfor %}
