-- Amount requested and Currency should read first in Payment Details, ahead
-- of Payee/supplier name and contact.
update form_field_config set sort_order = 1 where section = 'payment_details' and field_key = 'amount';
update form_field_config set sort_order = 2 where section = 'payment_details' and field_key = 'currency';
update form_field_config set sort_order = 3 where section = 'payment_details' and field_key = 'payee_name';
update form_field_config set sort_order = 4 where section = 'payment_details' and field_key = 'payee_contact';
