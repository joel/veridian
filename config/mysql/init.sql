-- Runs as root on first init of /var/lib/mysql

-- Ensure the app user exists before altering it
CREATE USER IF NOT EXISTS `veridian`@'%' IDENTIFIED BY '';

-- Enforce SSL for the app user
ALTER USER 'veridian'@'%' REQUIRE SSL;

-- Ensure all databases exist for Rails multi-DB
CREATE DATABASE IF NOT EXISTS `veridian_production`;
CREATE DATABASE IF NOT EXISTS `veridian_production_cache`;
CREATE DATABASE IF NOT EXISTS `veridian_production_queue`;
CREATE DATABASE IF NOT EXISTS `veridian_production_cable`;

-- Give 'veridian' full access to all of them
GRANT ALL PRIVILEGES ON `veridian_production`.*        TO 'veridian'@'%';
GRANT ALL PRIVILEGES ON `veridian_production_cache`.* TO 'veridian'@'%';
GRANT ALL PRIVILEGES ON `veridian_production_queue`.* TO 'veridian'@'%';
GRANT ALL PRIVILEGES ON `veridian_production_cable`.* TO 'veridian'@'%';

FLUSH PRIVILEGES;
