--------------------------------------------------------------------------------

{-# LANGUAGE DataKinds                 #-}
{-# LANGUAGE DeriveGeneric             #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE GADTSyntax                #-}
{-# LANGUAGE KindSignatures            #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiParamTypeClasses     #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TypeApplications          #-}
{-# LANGUAGE TypeFamilies              #-}

--------------------------------------------------------------------------------

-- | FIXME: doc
module EqSat
  ( module EqSat -- FIXME: specific export list
  ) where

--------------------------------------------------------------------------------

import           Control.Exception
                 (Exception, SomeException, catch, throw, throwIO)

import           Control.Applicative       (empty)

import           Control.Monad

import           Control.Monad.Primitive
import           Control.Monad.ST          (ST, runST)

import           Control.Monad.IO.Class    (MonadIO (liftIO))
import           Control.Monad.Trans.Class (MonadTrans (lift))
import qualified Control.Monad.Trans.Class as MonadTrans
import           Control.Monad.Trans.Maybe (MaybeT (MaybeT))
import qualified Control.Monad.Trans.Maybe as MaybeT

import           Control.Monad.Except      (MonadError (throwError))

import           Data.Hashable             (Hashable)

import qualified Data.HashMap.Strict       as HM
import qualified Data.HashSet              as HS

import qualified Data.Graph.Immutable      as Graph
import qualified Data.Graph.Mutable        as MGraph
import           Data.Graph.Types          (Graph, MGraph, SomeGraph, Vertex)
import qualified Data.Graph.Types          as Graph
import qualified Data.Graph.Types          as MGraph
import qualified Data.Graph.Types.Internal as Graph.Internal

import           Data.Partition            (Partition)
import qualified Data.Partition            as Partition

import           Data.STRef                (STRef)
import qualified Data.STRef                as STRef

import           Data.Maybe
import           Data.Ord                  (comparing)

import           Data.Foldable             (asum)
import           Data.List                 (sortBy)

import           Data.Map.Strict           (Map)
import qualified Data.Map.Strict           as Map

import           Data.Set                  (Set)
import qualified Data.Set                  as Set

import           Data.Word                 (Word16, Word32)

import           Data.Unique               (Unique)
import qualified Data.Unique               as Unique

import           Data.Vector               (Vector)
import qualified Data.Vector               as Vector

import           Data.Void                 (Void, absurd)

import           Data.SBV
                 (SBV, SInteger, Symbolic, (.<), (.<=), (.==))
import qualified Data.SBV                  as SBV
import qualified Data.SBV.Internals        as SBV.Internals

import           Flow                      ((.>), (|>))

import           GHC.Generics              (Generic)

import           EqSat.Internal.MHashMap   (MHashMap)
import qualified EqSat.Internal.MHashMap   as MHashMap

import           EqSat.Internal.MHashSet   (MHashSet)
import qualified EqSat.Internal.MHashSet   as MHashSet

import           EqSat.Variable            (Variable)
import qualified EqSat.Variable            as Variable

import           EqSat.Term
                 (ClosedTerm, OpenTerm, Term (MkNodeTerm, MkVarTerm))
import qualified EqSat.Term                as Term

import           EqSat.Equation            (Equation)
import qualified EqSat.Equation            as Equation

import           EqSat.Domain              (Domain)

import           EqSat.IsExpression
                 (IsExpression (exprToTerm, termToExpr))

--------------------------------------------------------------------------------

-- | FIXME: doc
type Edge g = (Vertex g, Vertex g)

-- | FIXME: doc
quotientGraph
  :: (Eq v, Hashable v)
  => ((Vertex g, v) -> (Vertex g, v))
  -- ^ FIXME: doc
  -> ((Edge g, e) -> (Edge g, e))
  -- ^ FIXME: doc
  -> Graph g e v
  -- ^ FIXME: doc
  -> Graph g e v
  -- ^ FIXME: doc
quotientGraph vf ef = undefined

-- | FIXME: doc
quotientSomeGraph
  :: (Eq v, Hashable v)
  => (forall g. (Vertex g, v) -> (Vertex g, v))
  -- ^ FIXME: doc
  -> (forall g. (Edge g, e) -> (Edge g, e))
  -- ^ FIXME: doc
  -> SomeGraph e v
  -- ^ FIXME: doc
  -> SomeGraph e v
  -- ^ FIXME: doc
quotientSomeGraph vf ef
  = Graph.mapSome (quotientGraph vf ef)

--------------------------------------------------------------------------------

-- | A 'PEG', or Program Expression Graph, is a rooted directed graph
--   representing a referentially transparent AST with sharing.
data PEG g node
  = UnsafeMkPEG
    !(Graph g Int (Unique, node))
    -- ^ The 'Graph' underlying the 'PEG'.
    !(Vertex g)
    -- ^ The root node of the 'PEG'.
  deriving ()

-- | Smart constructor for PEGs.
--
--   Postconditions:
--     * the underlying graph of the returned PEG will never have two
--       edges with the same label coming out of the same node.
--     * if you sort the children of a node by their edge labels in increasing
--       order, then you will recover the order of the children of that node in
--       the original subterm.
makePEG
  :: Term node (SomePEG node)
  -- ^ FIXME: doc
  -> PEG g node
  -- ^ FIXME: doc
makePEG = undefined

-- | FIXME: doc
makePEG'
  :: ClosedTerm node
  -- ^ FIXME: doc
  -> PEG g node
  -- ^ FIXME: doc
makePEG' = fmap absurd .> makePEG

-- | Get the root node of the 'Graph' underlying the given 'PEG'.
pegRoot
  :: PEG g node
  -- ^ FIXME: doc
  -> Vertex g
  -- ^ FIXME: doc
pegRoot (UnsafeMkPEG _ root) = root

-- | FIXME: doc
pegGraph
  :: PEG g node
  -- ^ FIXME: doc
  -> Graph g Int (Unique, node)
  -- ^ FIXME: doc
pegGraph (UnsafeMkPEG graph _) = graph

-- | FIXME: doc
pegAtVertex
  :: PEG g node
  -- ^ FIXME: doc
  -> Vertex g
  -- ^ FIXME: doc
  -> node
  -- ^ FIXME: doc
pegAtVertex peg vertex = snd (Graph.atVertex vertex (pegGraph peg))

-- | FIXME: doc
pegRootNode
  :: PEG g node
  -- ^ FIXME: doc
  -> node
  -- ^ FIXME: doc
pegRootNode peg = pegAtVertex peg (pegRoot peg)

-- | Given a 'PEG', return a 'Vector' of 'PEG's, each representing the subgraph
--   rooted at each child of the root node of the given 'PEG'.
pegChildren
  :: PEG g node
  -- ^ FIXME: doc
  -> Vector (PEG g node)
  -- ^ FIXME: doc
pegChildren = undefined -- FIXME
-- pegChildren node = let outgoing :: [(Int, GraphNode node Int)]
--                        outgoing = Set.toList (outgoingEdges (pegRoot node))
--                        children :: Vector (GraphNode node Int)
--                        children = Vector.fromList
--                                   (map snd (sortBy (comparing fst) outgoing))
--                    in Vector.map UnsafeMkPEG children

-- | Convert a 'PEG' into a term by starting at the root node and recursively
--   expanding nodes. If there is a cycle in the 'PEG', this will not terminate.
pegToTerm
  :: PEG g node
  -- ^ FIXME: doc
  -> ClosedTerm node
  -- ^ FIXME: doc
pegToTerm peg = MkNodeTerm
                (pegRootNode peg)
                (Vector.map pegToTerm (pegChildren peg))

-- | Modify a 'PEG', returning 'Nothing' if the modification you made to the
--   underlying 'Graph' made the 'PEG' no longer valid (e.g.: you added two
--   edges out of the same node with the same edge labels).
modifyPEG
  :: (Monad m)
  => PEG g node
  -- ^ FIXME: doc
  -> (Graph g Int node -> MaybeT m (Graph g' Int node))
  -- ^ FIXME: doc
  -> MaybeT m (PEG g' node)
  -- ^ FIXME: doc
modifyPEG peg f = do
  undefined

-- | FIXME: doc
normalizePEG
  :: PEG g node
  -- ^ FIXME: doc
  -> (Vertex g -> Vertex g, PEG g node)
  -- ^ FIXME: doc
normalizePEG input = runST $ do
  updaterHM <- MHashMap.new
  pegRef <- STRef.newSTRef input
  undefined
  updater <- undefined
  output  <- STRef.readSTRef pegRef
  pure (updater, output)

-- | FIXME: doc
traversePEG
  :: (Monad m)
  => PEG g nodeA
  -- ^ FIXME: doc
  -> (Vertex g -> nodeA -> m nodeB)
  -- ^ FIXME: doc
  -> m (PEG g nodeB)
  -- ^ FIXME: doc
traversePEG = undefined

--------------------------------------------------------------------------------

-- | FIXME: doc
data SomePEG node where
  -- | FIXME: doc
  MkSomePEG :: !(PEG g node) -> SomePEG node

-- | FIXME: doc
withSomePEG
  :: SomePEG node
  -- ^ FIXME: doc
  -> (forall g. PEG g node -> result)
  -- ^ FIXME: doc
  -> result
  -- ^ FIXME: doc
withSomePEG (MkSomePEG peg) f = f peg

--------------------------------------------------------------------------------

-- | An 'EPEG' (or equivalence PEG) is a 'PEG' along with an equivalence
--   relation on the 'PEG' nodes.
data EPEG g node
  = MkEPEG
    { epegPEG        :: !(PEG g node)
      -- ^ The underlying 'PEG'.
    , epegEqRelation :: !(Partition (Vertex g))
      -- ^ The equivalence relation on nodes.
    }
  deriving ()

-- | Return a 'Bool' representing whether the two given vertices are in the same
--   class of the equivalence relation contained in the given 'EPEG'.
epegEquivalent
  :: EPEG g node
  -- ^ FIXME: doc
  -> (Vertex g, Vertex g)
  -- ^ FIXME: doc
  -> Bool
  -- ^ FIXME: doc
epegEquivalent epeg (a, b)
  = let p = epegEqRelation epeg
    in Partition.rep p a == Partition.rep p b

-- | Given a pair of vertices in an 'EPEG', combine their equivalence classes.
epegAddEquivalence
  :: (Vertex g, Vertex g)
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> Maybe (EPEG g node)
  -- ^ FIXME: doc
epegAddEquivalence (a, b) epeg
  = if epegEquivalent epeg (a, b)
    then Nothing
    else Just (epeg { epegEqRelation = epegEqRelation epeg
                                       |> Partition.joinElems a b
                    })

-- | Convert a 'PEG' into the trivial 'EPEG' that holds every node to be
--   semantically distinct.
pegToEPEG
  :: PEG g node
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
pegToEPEG peg = MkEPEG peg Partition.discrete

-- | FIXME: doc
epegChildren
  :: EPEG g node
  -- ^ FIXME: doc
  -> Vector (EPEG g node)
  -- ^ FIXME: doc
epegChildren (MkEPEG peg eq) = (\p -> MkEPEG p eq) <$> pegChildren peg

-- | FIXME: doc
epegRootNode
  :: EPEG g node
  -- ^ FIXME: doc
  -> node
  -- ^ FIXME: doc
epegRootNode (MkEPEG peg _) = pegRootNode peg

-- | FIXME: doc
epegGetClass
  :: EPEG g node
  -- ^ FIXME: doc
  -> Vertex g
  -- ^ FIXME: doc
  -> Maybe (Set (Vertex g))
  -- ^ FIXME: doc
epegGetClass = undefined

-- | FIXME: doc
epegClasses
  :: EPEG g node
  -- ^ FIXME: doc
  -> Set (Set (Vertex g))
  -- ^ FIXME: doc
epegClasses = undefined

--------------------------------------------------------------------------------

-- | FIXME: doc
data SomeEPEG node where
  -- | FIXME: doc
  MkSomeEPEG :: !(EPEG g node) -> SomeEPEG node

-- | FIXME: doc
withSomeEPEG
  :: SomeEPEG node
  -- ^ FIXME: doc
  -> (forall g. EPEG g node -> result)
  -- ^ FIXME: doc
  -> result
  -- ^ FIXME: doc
withSomeEPEG (MkSomeEPEG epeg) f = f epeg

--------------------------------------------------------------------------------

-- | The type of global symbolic performance heuristics.
type GlobalSymbolicPerformanceHeuristic domain node
  = (forall g. EPEG g (node, SBV Bool) -> Symbolic (SBV domain))

-- | Optimize the given 'GlobalSymbolicPerformanceHeuristic' on the
--   given 'EPEG' via pseudo-boolean integer programming using @sbv@ / @Z3@'s
--   optimization support.
--
--   If the solver terminates successfully, a 'SomePEG' representing the
--   best selected sub-'PEG' is returned.
runGlobalSymbolicPerformanceHeuristic
  :: forall node domain m g.
     (MonadIO m, Domain domain)
  => EPEG g node
  -- ^ FIXME: doc
  -> GlobalSymbolicPerformanceHeuristic domain node
  -- ^ FIXME: doc
  -> m (Maybe (SomePEG node))
  -- ^ FIXME: doc
runGlobalSymbolicPerformanceHeuristic epeg heuristic = MaybeT.runMaybeT $ do
  let classesSet :: Set (Set (Vertex g))
      classesSet = epegClasses epeg

  let classes :: Vector (Int, Vector (Vertex g))
      classes = Set.toList classesSet
                |> map (Set.toList .> Vector.fromList)
                |> zip [0..]
                |> Vector.fromList

  optimizeResult <- liftIO $ SBV.optimize SBV.Lexicographic $ do
    predicates <- mconcat . Vector.toList <$> do
      Vector.forM classes $ \(i, cls) -> do
        let n = Vector.length cls
        when (toInteger n > toInteger (maxBound :: Word16)) $ do
          error "Size of equivalence class is too large!"
        var <- SBV.sWord16 (show i)
        -- SBV.constrain (0 .<= var)
        SBV.constrain (var .< fromIntegral n)
        let vec = Vector.fromList (zip ([0..] :: [Int]) (Vector.toList cls))
        Vector.forM vec $ \(j, vertex) -> do
          pure (vertex, var .== fromIntegral j)
    let predMap = HM.fromList (Vector.toList predicates)
    peg <- traversePEG (epegPEG epeg) $ \vertex node -> do
      case HM.lookup vertex predMap of
        Just b  -> pure (node, b)
        Nothing -> error "this should never happen"
    goal <- heuristic (MkEPEG peg (epegEqRelation epeg))
    SBV.maximize "heuristic" goal

  (SBV.LexicographicResult result) <- pure optimizeResult

  let getValue :: Int -> MaybeT m Word32
      getValue i = SBV.getModelValue (show i) result |> pure |> MaybeT

  vertices <- Vector.forM classes $ \(i, cls) -> do
    value <- getValue i -- default?
    Vector.indexM cls (fromIntegral value)

  let vertexSet = HS.fromList (Vector.toList vertices)

  let keepVertex = HS.member vertexSet

  rootClass <- MaybeT (pure (epegGetClass epeg (pegRoot (epegPEG epeg))))

  root <- Vector.filter (`Set.member` rootClass) vertices
          |> Vector.toList
          |> \case [x] -> pure x
                   _   -> empty

  representativeMap <- pure $ runST $ do
    hm <- MHashMap.new @_ @(Vertex g) @(Vertex g)
    undefined
    -- Vector.forM_
    MHashMap.freeze hm

  modifyPEG (epegPEG epeg) $ \graph -> do
    -- pure $ flip Graph.mapVertices graph $ \vertex label -> do
      -- fmap Graph.Internal.Graph $ Graph.create $ \mgraph -> do
      --   undefined
      -- -- case graph of
      -- --    MkSomePEG (UnsafeMkPEG)
      -- undefined
    undefined
  -- let convertModel :: SMTModel
  -- case result of
  --   SBV.Satisfiable
  undefined

--------------------------------------------------------------------------------

class Heuristic heuristic where
  runHeuristic
    :: (MonadIO m)
    => EPEG g node
    -> heuristic node
    -> m (Maybe (SomePEG node))

instance (Domain d) => Heuristic (GlobalSymbolicPerformanceHeuristic d) where
  runHeuristic = runGlobalSymbolicPerformanceHeuristic

--------------------------------------------------------------------------------

-- | FIXME: doc
matchPattern
  :: forall node var g.
     (Eq node, Ord var, Hashable var)
  => Term node var
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> Maybe (HM.HashMap var (EPEG g node))
  -- ^ FIXME: doc
matchPattern = do
  let go :: forall s.
            MHashMap s var (EPEG g node)
         -> Term node var
         -> EPEG g node
         -> MaybeT (ST s) ()
      go hm term epeg
        = case term of
            (MkVarTerm var) -> do
              -- This is the equivalence relation under which non-linear pattern
              -- matches are checked. Currently it checks that the two nodes are
              -- exactly equal, so this means that matching will sometimes fail
              -- if the graph does not have maximal sharing.
              let equiv :: EPEG g node -> EPEG g node -> Bool
                  equiv a b = pegRoot (epegPEG a) == pegRoot (epegPEG b)
              MHashMap.insertWith hm var epeg
                $ \a b -> guard (a `equiv` b) >> pure a
            (MkNodeTerm node children) -> do
              let pairs = Vector.zip children (epegChildren epeg)
              guard (node == epegRootNode epeg)
              Vector.forM_ pairs $ \(subpat, subgraph) -> do
                go hm subpat subgraph
  \term epeg -> runST $ MaybeT.runMaybeT $ do
    hm <- MHashMap.new
    go hm term epeg
    MHashMap.freeze hm

-- | FIXME: doc
applyRule
  :: forall node var g.
     (Eq node, Ord var, Hashable var)
  => (Term node var, Term node var)
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> Maybe (EPEG g node)
  -- ^ FIXME: doc
applyRule (pat, rep) epeg = runST $ MaybeT.runMaybeT $ do
  -- peg <- epegPEG epeg
  undefined

--------------------------------------------------------------------------------

-- | Given a performance heuristic and an 'EPEG', return the 'PEG' subgraph that
--   maximizes the heuristic.
selectBest
  :: (Heuristic heuristic)
  => heuristic node
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> PEG g node
  -- ^ FIXME: doc
selectBest heuristic epeg = undefined

-- | Given a 'Set' of 'Equation's and an 'EPEG', this will return a new 'EPEG'
--   that is the result of matching and applying one of the equations to the
--   'EPEG'. If there is no place in the 'EPEG' where any of the equations apply
--   (or if the result of applying the equation is something that is already in
--   the graph), then this function will return 'Nothing'.
saturateStep
  :: Set (Equation node Variable)
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> Maybe (EPEG g node)
  -- ^ FIXME: doc
saturateStep eqs epeg = do
  undefined

-- | The internal version of equality saturation.
saturate
  :: (Monad m, Heuristic heuristic)
  => Set (Equation node Variable)
  -- ^ FIXME: doc
  -> heuristic node
  -- ^ FIXME: doc
  -> EPEG g node
  -- ^ FIXME: doc
  -> (EPEG g node -> m Bool)
  -- ^ FIXME: doc
  -> (PEG g node -> m (Maybe a))
  -- ^ FIXME: doc
  -> m [a]
  -- ^ FIXME: doc
saturate eqs heuristic initial timer cb = do
  let go epeg soFar = do
        case saturateStep eqs epeg of
          Just epeg' -> do let recurse = go epeg'
                           shouldSelectBest <- timer epeg'
                           if shouldSelectBest
                             then cb (selectBest heuristic epeg')
                                  >>= \case (Just x) -> recurse (x : soFar)
                                            Nothing  -> recurse soFar
                             else recurse soFar
          Nothing    -> pure soFar
  go initial []

-- | The public interface of equality saturation.
equalitySaturation
  :: forall node heuristic expr m a.
     ( IsExpression node expr, MonadError SomeException m
     , Heuristic heuristic )
  => Set (Equation node Variable)
  -- ^ A set of optimization axioms.
  -> heuristic node
  -- ^ The performance heuristic to optimize.
  -> expr
  -- ^ The code whose performance will be optimized.
  -> (forall g. EPEG g node -> m Bool)
  -- ^ A callback that, given the current state of the 'EPEG', will decide
  --   whether we should run 'selectBest' again. In many cases, this will be
  --   some kind of timer.
  -> (expr -> m (Maybe a))
  -- ^ A callback that will be called with the optimized 'Term' every time
  --   'selectBest' has found a new best version of the original program.
  --   The argument is the new best version, and the return value will be
  --   collected in a list during the equality saturation loop. If 'Nothing'
  --   is ever returned by this callback, equality saturation will terminate
  --   early; otherwise it will run for an amount of time that is exponential
  --   in the size of the original program.
  -> m [a]
  -- ^ The list of results produced by the second callback, in _reverse_
  --   chronological order (e.g.: starting with newest and ending with oldest).
equalitySaturation eqs heuristic initial timer cb
  = let exprToEPEG = exprToTerm .> makePEG' .> pegToEPEG
        pegToExpr peg = case termToExpr (pegToTerm peg) of
                          Left  exception -> throwError exception
                          Right result    -> pure result
    in saturate eqs heuristic (exprToEPEG initial) timer (pegToExpr >=> cb)

--------------------------------------------------------------------------------
