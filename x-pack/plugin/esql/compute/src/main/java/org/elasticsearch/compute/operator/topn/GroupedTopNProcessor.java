/*
 * Copyright Elasticsearch B.V. and/or licensed to Elasticsearch B.V. under one
 * or more contributor license agreements. Licensed under the Elastic License
 * 2.0; you may not use this file except in compliance with the Elastic License
 * 2.0.
 */

package org.elasticsearch.compute.operator.topn;

import org.elasticsearch.common.breaker.CircuitBreaker;
import org.elasticsearch.compute.aggregation.GroupingAggregatorFunction;
import org.elasticsearch.compute.aggregation.blockhash.BlockHash;
import org.elasticsearch.compute.data.BlockFactory;
import org.elasticsearch.compute.data.ElementType;
import org.elasticsearch.compute.data.IntArrayBlock;
import org.elasticsearch.compute.data.IntBigArrayBlock;
import org.elasticsearch.compute.data.IntVector;
import org.elasticsearch.compute.data.Page;

import java.util.List;
import java.util.stream.IntStream;

/**
 * A {@link TopNProcessor} for grouped top-N operations. Uses a {@link BlockHash} to efficiently
 * map group key columns to integer group IDs, and routes rows to per-group priority queues.
 */
class GroupedTopNProcessor implements TopNProcessor {
    private final int[] groupChannels;
    private final BlockHash blockHash;
    private final BlockFactory blockFactory;

    GroupedTopNProcessor(int[] groupChannels, List<ElementType> elementTypes, BlockFactory blockFactory, int maxPageSize) {
        this.groupChannels = groupChannels;
        this.blockFactory = blockFactory;
        List<BlockHash.GroupSpec> groupSpecs = IntStream.of(groupChannels)
            .mapToObj(ch -> new BlockHash.GroupSpec(ch, elementTypes.get(ch)))
            .toList();
        this.blockHash = BlockHash.build(groupSpecs, blockFactory, maxPageSize, false);
    }

    @Override
    public RowFiller rowFiller(
        List<ElementType> elementTypes,
        List<TopNEncoder> encoders,
        List<TopNOperator.SortOrder> sortOrders,
        boolean[] channelInKey,
        Page page
    ) {
        int[] groupIds = computeGroupIds(page);
        return new GroupedRowFiller(elementTypes, encoders, sortOrders, channelInKey, groupIds, page);
    }

    /**
     * Uses the BlockHash to compute group IDs for all positions in the page.
     * Each position is assigned a single integer group ID.
     */
    private int[] computeGroupIds(Page page) {
        int positionCount = page.getPositionCount();
        int[] ids = new int[positionCount];
        blockHash.add(page, new GroupingAggregatorFunction.AddInput() {
            @Override
            public void add(int positionOffset, IntVector groupIds) {
                for (int i = 0; i < groupIds.getPositionCount(); i++) {
                    ids[positionOffset + i] = groupIds.getInt(i);
                }
            }

            @Override
            public void add(int positionOffset, IntArrayBlock groupIds) {
                for (int i = 0; i < groupIds.getPositionCount(); i++) {
                    // For multivalued group keys, take the first value.
                    ids[positionOffset + i] = groupIds.getInt(groupIds.getFirstValueIndex(i));
                }
            }

            @Override
            public void add(int positionOffset, IntBigArrayBlock groupIds) {
                for (int i = 0; i < groupIds.getPositionCount(); i++) {
                    // For multivalued group keys, take the first value.
                    ids[positionOffset + i] = groupIds.getInt(groupIds.getFirstValueIndex(i));
                }
            }

            @Override
            public void close() {
                // Nothing to close
            }
        });
        return ids;
    }

    @Override
    public Row row(CircuitBreaker breaker, List<TopNOperator.SortOrder> sortOrders, RowFiller filler) {
        GroupedRowFiller groupedFiller = (GroupedRowFiller) filler;
        return new GroupedRow(breaker, groupedFiller.preAllocatedKeysSize(), groupedFiller.preAllocatedValueSize());
    }

    @Override
    public TopNQueue queue(CircuitBreaker breaker, int topCount) {
        return new GroupedQueue(breaker, blockFactory.bigArrays(), topCount);
    }

    @Override
    public void close() {
        blockHash.close();
    }
}
