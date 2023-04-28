// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

interface ITaxProcessor {
  function distributeTaxes( uint depositBalance, uint marketingBalance, address targetToken ) external;
}