--------------------------------------------------------------------------------

-- | FIXME: doc
module EqSat.Equation
  ( Equation
  , make
  , from
  , boundVariables
  , getLHS
  , getRHS
  ) where

--------------------------------------------------------------------------------

import           Control.Monad (guard)

import           Data.Set      (Set)
import qualified Data.Set      as Set

import           EqSat.Term    (Term, freeVars)
import qualified EqSat.Term    as Term

--------------------------------------------------------------------------------

-- | FIXME: doc
data Equation node var
  = UnsafeMkEquation
    !(Term node var)
    !(Term node var)
    !(Set var)
  deriving (Eq, Ord)

--------------------------------------------------------------------------------

-- | Smart constructor for 'Equation's.
--
--   The set of free variables in the given right-hand side must be a subset
--   of the set of free variables in the given left-hand side, or else 'Nothing'
--   will be returned.
--
--   Laws:
--   * For any @(lhs, rhs) ∈ ('Term' node var, 'Term' node var)@,
--     @'Set.isSubsetOf' ('freeVars' rhs) ('freeVars' lhs) ≡ 'True'@
--     implies that
--     @'fromEquation' '<$>' 'makeEquation' (lhs, rhs) ≡ 'Just' (lhs, rhs)@.
--   * For any @(lhs, rhs) ∈ ('Term' node var, 'Term' node var)@,
--     @'Set.isSubsetOf' ('freeVars' rhs) ('freeVars' lhs) ≡ 'False'@
--     implies that @'makeEquation' (lhs, rhs) ≡ 'Nothing'@.
make
  :: (Ord var)
  => (Term node var, Term node var)
  -- ^ A pair @(lhs, rhs)@ containing the left- and right-hand sides
  --   respectively of the would-be equation.
  -> Maybe (Equation node var)
  -- ^ The equation, if the given @(lhs, rhs)@ pair was valid.
make (rhs, lhs) = do
  let (freeLHS, freeRHS) = (freeVars lhs, freeVars rhs)
  guard (freeRHS `Set.isSubsetOf` freeLHS)
  pure (UnsafeMkEquation lhs rhs freeLHS)

-- | Get a pair containing the left- and right-hand sides of the given equation.
from
  :: Equation node var
  -- ^ An equation.
  -> (Term node var, Term node var)
  -- ^ A pair @(lhs, rhs)@ containing the left- and right-hand sides
  --   respectively of the given equation.
from (UnsafeMkEquation lhs rhs _) = (lhs, rhs)

-- | Get the set of variables bound in this equation by the left-hand side.
boundVariables
  :: Equation node var
  -- ^ An equation.
  -> Set var
  -- ^ The set of variables bound in this equation by the left-hand side.
boundVariables (UnsafeMkEquation _ _ bounds) = bounds

-- | Helper function for getting the left-hand side of an equation.
getLHS
  :: Equation node var
  -- ^ An equation.
  -> Term node var
  -- ^ The left-hand side of the given equation.
getLHS = fst . from

-- | Helper function for getting the right-hand side of an equation.
getRHS
  :: Equation node var
  -- ^ An equation.
  -> Term node var
  -- ^ The right-hand side of the given equation.
getRHS = snd . from

--------------------------------------------------------------------------------
