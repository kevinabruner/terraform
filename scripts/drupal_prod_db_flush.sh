#!/bin/bash
cd /var/www/html
echo "--- Starting Drupal Prod db cache flush: $(date) ---" >> /var/log/cloud-init-drupal.log
sudo -u www-data environment=${each.value.env} /var/www/vendor/drush/drush/drush cr -y >> /var/log/cloud-init-drupal.log 2>&1 || true
sudo -u www-data environment=${each.value.env} /var/www/vendor/drush/drush/drush updb -y >> /var/log/cloud-init-drupal.log 2>&1 || true
sudo -u www-data environment=${each.value.env} /var/www/vendor/drush/drush/drush cim -y >> /var/log/cloud-init-drupal.log 2>&1 || truea