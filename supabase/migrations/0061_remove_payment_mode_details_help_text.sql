update form_field_config set help_text = null
  where section = 'payment_details' and field_key = 'payment_mode_details';
