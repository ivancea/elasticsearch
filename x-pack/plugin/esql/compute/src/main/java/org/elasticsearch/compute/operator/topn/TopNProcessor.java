/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.compute.data.Block;
import org.elasticsearch.compute.data.ElementType;
import org.elasticsearch.compute.data.Page;
import org.elasticsearch.core.Releasable;

import java.util.List;

interface TopNProcessor extends Releasable {
    RowFiller rowFiller(
        List<ElementType> elementTypes,
        List<TopNEncoder> encoders,
        List<TopNOperator.SortOrder> sortOrders,
        boolean[] channelInKey,
        Page page
    );

    Row row(CircuitBreaker breaker, List<TopNOperator.SortOrder> sortOrders, RowFiller rowFiller);

    TopNQueue queue(CircuitBreaker breaker, int topCount);

    /**
     * Returns the expanded (single-value) key blocks from the BlockHash, one per group key channel.
     * Returns {@code null} for ungrouped top-N.
     * <p>
     * The caller is responsible for closing the returned blocks.
     */
    Block[] getGroupKeyBlocks();

    /**
     * Returns an array mapping group IDs to positions in the blocks returned by {@link #getGroupKeyBlocks()}.
     * Group IDs from BlockHash may not be 0-based, so this mapping is needed.
     * Returns {@code null} for ungrouped top-N.
     */
    int[] getGroupIdToKeyPosition();
}
