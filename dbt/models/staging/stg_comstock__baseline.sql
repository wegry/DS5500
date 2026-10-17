-- ComStock baseline (upgrade 0): one row per model per census tract.
select * exclude (comstock_upgrade_key, upgrade_id, upgrade_name, applicability)
from {{ ref('stg_comstock__upgrades') }}
where upgrade_id = 0
