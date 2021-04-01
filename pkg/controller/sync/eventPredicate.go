// Copyright (c) 2020 Red Hat, Inc.
// Copyright Contributors to the Open Cluster Management project

package sync

import (
	policiesv1 "github.com/open-cluster-management/governance-policy-propagator/pkg/apis/policies/v1"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

var policiesv1APIVersion = policiesv1.SchemeGroupVersion.Group + "/" + policiesv1.SchemeGroupVersion.Version

var eventPredicateFuncs = predicate.Funcs{
	UpdateFunc: func(e event.UpdateEvent) bool {
		eventObjNew := e.ObjectNew.(*corev1.Event)
		// eventObjOld := e.ObjectOld.(*corev1.Event)
		if eventObjNew.InvolvedObject.Kind == policiesv1.Kind &&
			eventObjNew.InvolvedObject.APIVersion == policiesv1APIVersion {
			return true
		}
		return false
	},
	CreateFunc: func(e event.CreateEvent) bool {
		eventObj := e.Object.(*corev1.Event)
		if eventObj.InvolvedObject.Kind == policiesv1.Kind &&
			eventObj.InvolvedObject.APIVersion == policiesv1APIVersion {
			return true
		}
		return false
	},
	GenericFunc: func(e event.GenericEvent) bool {
		eventObj := e.Object.(*corev1.Event)
		if eventObj.InvolvedObject.Kind == policiesv1.Kind &&
			eventObj.InvolvedObject.APIVersion == policiesv1APIVersion {
			return true
		}
		return false
	},
	DeleteFunc: func(e event.DeleteEvent) bool {
		return false
	},
}
