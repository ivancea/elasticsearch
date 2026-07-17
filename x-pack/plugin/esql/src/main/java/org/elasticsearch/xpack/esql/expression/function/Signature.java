/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.xpack.esql.expression.function;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/**
 * One concrete overload of a function: argument types plus return type.
 * <p>
 *     A parameter entry may use {@code |} to declare a within-signature union
 *     (e.g. {@code "date|keyword|text"}), which is expanded to the cartesian
 *     product of those types when validating tests and generating docs.
 * </p>
 */
@Retention(RetentionPolicy.RUNTIME)
@Target({})
public @interface Signature {
    /**
     * Argument types for this overload. Optional trailing parameters are omitted
     * rather than listed as nullable. Use {@code |} for a union in one position.
     */
    String[] params();

    /**
     * The return type of this overload.
     */
    String returnType();
}
