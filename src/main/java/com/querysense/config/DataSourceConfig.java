package com.querysense.config;

import javax.sql.DataSource;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;

@Configuration
public class DataSourceConfig {

    // PRIMARY: Application database — used by JPA, Flyway, all application repositories
    @Bean
    @Primary
    @ConfigurationProperties("spring.datasource.app")
    public DataSourceProperties appDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean
    @Primary
    public DataSource appDataSource() {
        return appDataSourceProperties()
                .initializeDataSourceBuilder()
                .build();
    }

    // ANALYTICS QUERY EXECUTION: read-only role, SELECT privileges only
    // Used exclusively by SafeQueryExecutor
    @Bean("analyticsDataSourceProperties")
    @ConfigurationProperties("spring.datasource.analytics")
    public DataSourceProperties analyticsDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean("analyticsDataSource")
    public DataSource analyticsDataSource() {
        return analyticsDataSourceProperties()
                .initializeDataSourceBuilder()
                .build();
    }

    // ANALYTICS INTROSPECTION: reads information_schema only
    // Used exclusively by SchemaIntrospector — NEVER on query execution path
    @Bean("introspectDataSourceProperties")
    @ConfigurationProperties("spring.datasource.introspect")
    public DataSourceProperties introspectDataSourceProperties() {
        return new DataSourceProperties();
    }

    @Bean("introspectDataSource")
    public DataSource introspectDataSource() {
        return introspectDataSourceProperties()
                .initializeDataSourceBuilder()
                .build();
    }

    // PRIMARY: JdbcTemplate for application database (appDataSource)
    // Required so Spring AI pgvector auto-configuration resolves an unambiguous JdbcTemplate
    @Bean
    @Primary
    public JdbcTemplate appJdbcTemplate(
            @Qualifier("appDataSource") DataSource appDataSource) {
        return new JdbcTemplate(appDataSource);
    }

    // JdbcTemplate for query execution (analyticsDataSource)
    @Bean("analyticsJdbcTemplate")
    public JdbcTemplate analyticsJdbcTemplate(
            @Qualifier("analyticsDataSource") DataSource analyticsDataSource) {
        return new JdbcTemplate(analyticsDataSource);
    }

    // JdbcTemplate for schema introspection (introspectDataSource)
    @Bean("introspectJdbcTemplate")
    public JdbcTemplate introspectJdbcTemplate(
            @Qualifier("introspectDataSource") DataSource introspectDataSource) {
        return new JdbcTemplate(introspectDataSource);
    }
}
