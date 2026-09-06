data:extend{
  {
    type = 'bool-setting',
    name = 'rq-notifications',
    order = 'a',
    setting_type = 'runtime-per-user',
    default_value = true,
  },
  {
    type = 'bool-setting',
    name = 'rq-pause-game',
    order = 'b',
    setting_type = 'runtime-per-user',
    default_value = false,
  },
  {
    type = 'string-setting',
    name = 'rq-sync',
    order = 'a',
    setting_type = 'runtime-global',
    default_value = 'hybrid',
    allowed_values = {
      'disabled',
      'sync',
      'wait',
      'freeze',
      'move-head',
      'move-tail',
      'hybrid'
    }
  }
}
